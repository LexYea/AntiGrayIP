#!/bin/sh
# antigrayip.sh - watch one or more WAN IPs, restart the affected interface
# while the ISP hands out a private/CGNAT ("gray") address, until a public
# ("white") address is obtained. Supports dual-WAN / several WAN ports:
# each interface listed in antigrayip.settings.interface is checked and
# reconnected independently.
#
# Gray/private ranges are read from the editable UCI list
# antigrayip.settings.gray_subnet (CIDR notation). If that list is empty
# (e.g. an older config kept as-is across an update), a built-in default
# set - matching Rostelecom's CGNAT pool - is used instead.

. /lib/functions.sh
. /lib/functions/network.sh

CFG=antigrayip
STATE_DIR=/var/run/antigrayip
DEFAULT_SUBNETS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16"
DEFAULT_IFACES="wan"

mkdir -p "$STATE_DIR"

log() {
	local msg="$1"
	[ -n "$log_file" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$log_file" 2>/dev/null
	logger -t antigrayip "$msg"
}

load_cfg() {
	config_load "$CFG"
	config_get enabled        settings enabled        '1'
	config_get interval       settings interval       '30'
	config_get retry_delay    settings retry_delay    '10'
	config_get max_retries    settings max_retries    '5'
	config_get escalate_reboot settings escalate_reboot '0'
	config_get escalate_after settings escalate_after '10'
	config_get log_file       settings log_file       '/var/log/antigrayip.log'
}

# Monitored interfaces come from the editable UCI list "interface"; works
# uniformly whether it's a modern "list interface '...'" (possibly several
# entries) or a legacy single "option interface 'wan'" from an older config.
get_ifaces() {
	local out
	out="$(uci -q get "${CFG}.settings.interface")"
	[ -z "$out" ] && out="$DEFAULT_IFACES"
	echo "$out"
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

# --- per-interface fail-count persistence (survives loop iterations) ------

iface_id() {
	echo "$1" | tr -c 'A-Za-z0-9_' '_'
}

read_fail() {
	local f="$STATE_DIR/fail.$(iface_id "$1")"
	[ -f "$f" ] && cat "$f" || echo 0
}

write_fail() {
	echo "$2" > "$STATE_DIR/fail.$(iface_id "$1")"
}

# ---------------------------------------------------------------------------

check_iface() {
	local iface="$1" ip fc

	fc="$(read_fail "$iface")"

	network_flush_cache
	ip=""
	network_get_ipaddr ip "$iface"

	if [ -z "$ip" ]; then
		log "[$iface] нет адреса"
		return
	fi

	if is_private_ip "$ip"; then
		fc=$((fc + 1))
		write_fail "$iface" "$fc"
		log "[$iface] серый IP: $ip (попытка $fc)"

		if [ "$escalate_reboot" = "1" ] && [ "$fc" -ge "${escalate_after:-10}" ]; then
			log "[$iface] порог эскалации ($escalate_after) достигнут, перезагрузка роутера"
			sync
			reboot
			exit 0
		fi

		if [ "$fc" = "${max_retries:-5}" ]; then
			log "[$iface] ПРЕДУПРЕЖДЕНИЕ: всё ещё серый после $max_retries попыток подряд"
		fi

		log "[$iface] перезапуск интерфейса"
		ifdown "$iface" 2>/dev/null
		sleep 2
		ifup "$iface" 2>/dev/null
		sleep "${retry_delay:-10}"
	else
		[ "$fc" -gt 0 ] && log "[$iface] белый IP получен: $ip"
		write_fail "$iface" 0
	fi
}

load_cfg

while true; do
	load_cfg

	if [ "$enabled" != "1" ]; then
		sleep "${interval:-30}"
		continue
	fi

	for iface in $(get_ifaces); do
		check_iface "$iface"
	done

	sleep "${interval:-30}"
done
