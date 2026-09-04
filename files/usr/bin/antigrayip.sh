#!/bin/sh
# antigrayip.sh - watch WAN IP, restart WAN while ISP hands out a private/CGNAT
# ("gray") address, stop once a public ("white") address is obtained.
#
# Gray/private ranges are read from the editable UCI list
# antigrayip.settings.gray_subnet (CIDR notation). If that list is empty
# (e.g. an older config kept as-is across an update), a built-in default
# set - matching Rostelecom's CGNAT pool - is used instead.

. /lib/functions.sh
. /lib/functions/network.sh

CFG=antigrayip
DEFAULT_SUBNETS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16"

log() {
	local msg="$1"
	[ -n "$log_file" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$log_file" 2>/dev/null
	logger -t antigrayip "$msg"
}

load_cfg() {
	config_load "$CFG"
	config_get enabled        settings enabled        '1'
	config_get iface          settings interface      'wan'
	config_get interval       settings interval       '30'
	config_get retry_delay    settings retry_delay    '10'
	config_get max_retries    settings max_retries    '5'
	config_get escalate_reboot settings escalate_reboot '0'
	config_get escalate_after settings escalate_after '10'
	config_get log_file       settings log_file       '/var/log/antigrayip.log'
}

# --- CIDR matching (pure POSIX shell, no ipcalc/awk dependency) -----------

ip2int() {
	local o1 o2 o3 o4 oldifs="$IFS"
	IFS=.
	set -- $1
	IFS="$oldifs"
	o1=$1; o2=$2; o3=$3; o4=$4
	echo $(( (o1 * 16777216) + (o2 * 65536) + (o3 * 256) + o4 ))
}

in_subnet() {
	# $1 = ip, $2 = cidr (a.b.c.d/n)
	local ip="$1" cidr="$2" net bits ip_int net_int size lo hi
	net="${cidr%/*}"
	bits="${cidr#*/}"
	case "$bits" in ''|*[!0-9]*) return 1 ;; esac
	[ "$bits" -ge 0 ] && [ "$bits" -le 32 ] || return 1

	ip_int="$(ip2int "$ip")"
	net_int="$(ip2int "$net")"

	if [ "$bits" -ge 32 ]; then
		size=1
	else
		size=$(( 1 << (32 - bits) ))
	fi

	lo="$net_int"
	hi=$(( net_int + size - 1 ))

	[ "$ip_int" -ge "$lo" ] 2>/dev/null && [ "$ip_int" -le "$hi" ] 2>/dev/null
}

GRAY_MATCH=0
GRAY_COUNT=0
CHECK_IP=""

check_subnet_cb() {
	GRAY_COUNT=$((GRAY_COUNT + 1))
	in_subnet "$CHECK_IP" "$1" && GRAY_MATCH=1
}

is_private_ip() {
	CHECK_IP="$1"
	GRAY_MATCH=0
	GRAY_COUNT=0
	config_list_foreach settings gray_subnet check_subnet_cb

	if [ "$GRAY_COUNT" -eq 0 ]; then
		local s
		for s in $DEFAULT_SUBNETS; do
			if in_subnet "$CHECK_IP" "$s"; then
				GRAY_MATCH=1
				break
			fi
		done
	fi

	[ "$GRAY_MATCH" -eq 1 ]
}

# ---------------------------------------------------------------------------

get_wan_ip() {
	local ipaddr
	network_flush_cache
	network_get_ipaddr ipaddr "$iface"
	echo "$ipaddr"
}

reconnect() {
	log "restarting interface '$iface'"
	ifdown "$iface" 2>/dev/null
	sleep 2
	ifup "$iface" 2>/dev/null
}

fail_count=0
load_cfg

while true; do
	load_cfg

	if [ "$enabled" != "1" ]; then
		fail_count=0
		sleep "${interval:-30}"
		continue
	fi

	ip="$(get_wan_ip)"

	if [ -z "$ip" ]; then
		log "interface '$iface' has no address yet"
	elif is_private_ip "$ip"; then
		fail_count=$((fail_count + 1))
		log "gray IP on '$iface': $ip (attempt $fail_count)"

		if [ "$escalate_reboot" = "1" ] && [ "$fail_count" -ge "${escalate_after:-10}" ]; then
			log "escalation threshold ($escalate_after) reached, rebooting router"
			sync
			reboot
			exit 0
		fi

		if [ "$fail_count" = "${max_retries:-5}" ]; then
			log "WARNING: still gray after $max_retries attempts, continuing"
		fi

		reconnect
		sleep "${retry_delay:-10}"
		continue
	else
		[ "$fail_count" -gt 0 ] && log "white IP obtained on '$iface': $ip"
		fail_count=0
	fi

	sleep "${interval:-30}"
done
