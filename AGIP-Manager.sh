#!/bin/sh
# ============================================================
#  AGIP-Manager.sh — установка/обновление/статус/удаление
#  AntiGrayIP для OpenWrt (онлайн, с GitHub)
#
#  by LexYea | aedev.ru
#  https://github.com/LexYea/AntiGrayIP
#
#  Запуск одной командой на роутере (интерактивное меню):
#    sh <(wget -qO - 'https://raw.githubusercontent.com/LexYea/AntiGrayIP/main/AGIP-Manager.sh')
#
#  Или сразу нужным действием:
#    sh <(wget -qO - '.../AGIP-Manager.sh') install|update|status|remove|purge
#    sh <(wget -qO - '.../AGIP-Manager.sh') update force   # обновить, даже если версия та же
#
#  Для установки/удаления БЕЗ интернета (пакет скопирован на устройство
#  заранее) используйте самостоятельные agip-install.sh / agip-uninstall.sh -
#  они не зависят от этого файла и работают полностью офлайн.
#
#  OpenWrt 25.x использует apk вместо opkg - см. подсказки ниже при ошибке
#  скачивания.
# ============================================================

MANAGER_VERSION="1.1.1"   # держите в паре с /VERSION в репозитории

REPO_USER="LexYea"
REPO_NAME="AntiGrayIP"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"
MANAGER_URL="${RAW_BASE}/AGIP-Manager.sh"
MANAGER_LOCAL="/usr/bin/agip-manager.sh"
MARKER="/usr/lib/antigrayip.files"
VERSION_LOCAL="/usr/lib/antigrayip.version"

# repo_path : dest_path : mode ("config" для UCI-файла, либо chmod-октал) : ожидаемое начало файла (для проверки перед установкой)
FILES="files/etc/config/antigrayip:/etc/config/antigrayip:config:config antigrayip
files/usr/bin/antigrayip.sh:/usr/bin/antigrayip.sh:0755:#!/bin/sh
files/etc/init.d/antigrayip:/etc/init.d/antigrayip:0755:#!/bin/sh /etc/rc.common
files/etc/hotplug.d/iface/95-antigrayip:/etc/hotplug.d/iface/95-antigrayip:0755:#!/bin/sh
files/usr/share/rpcd/acl.d/luci-app-antigrayip.json:/usr/share/rpcd/acl.d/luci-app-antigrayip.json:0644:{
files/usr/share/luci/menu.d/luci-mod-antigrayip.json:/usr/share/luci/menu.d/luci-mod-antigrayip.json:0644:{
files/www/luci-static/resources/view/antigrayip.js:/www/luci-static/resources/view/antigrayip.js:0644:'use strict';"

banner() {
	local v=""
	[ -f "$VERSION_LOCAL" ] && v="   Установлено: v$(cat "$VERSION_LOCAL")"
	cat << EOF
================================================================
   AntiGrayIP manager  —  by LexYea  (aedev.ru)
   https://aedev.ru   |   https://github.com/LexYea/AntiGrayIP
   Менеджер v${MANAGER_VERSION}${v}
================================================================
EOF
}

fetch() {
	# $1 = url  $2 = dest file
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1" -o "$2"
	else
		wget -qO "$2" "$1"
	fi
}

fetch_text() {
	# echoes remote text content (one line), or nothing on failure
	local t="/tmp/agip_txt.$$"
	if fetch "$1" "$t" 2>/dev/null; then
		tr -d '\r\n' < "$t"
	fi
	rm -f "$t"
}

downloader_hint() {
	echo "Проверьте, что на роутере есть рабочий HTTPS-загрузчик (curl или wget с SSL):"
	if command -v apk >/dev/null 2>&1; then
		echo "  apk update && apk add wget curl"
	else
		echo "  opkg update && opkg install wget-ssl"
	fi
}

# Скачивает файл во временное место и проверяет, что он начинается с
# ожидаемой сигнатуры, прежде чем подменить боевой файл. Защита от ситуации,
# когда под нужным именем приходит совсем не то содержимое.
verify_and_install() {
	# $1=tmpfile $2=dst $3=expected_prefix $4=kind
	local tmp="$1" dst="$2" prefix="$3" kind="$4" first_line

	if [ ! -s "$tmp" ]; then
		echo "  ! получен пустой файл: $dst"
		return 1
	fi

	first_line="$(head -n 1 "$tmp")"
	case "$first_line" in
		"$prefix"*) : ;;
		*)
			echo "  ! содержимое не прошло проверку: $dst"
			echo "    ожидалось начало : $prefix"
			echo "    получено         : $first_line"
			return 1
			;;
	esac

	mkdir -p "$(dirname "$dst")"
	mv "$tmp" "$dst"
	[ "$kind" != "config" ] && chmod "$kind" "$dst" 2>/dev/null
	return 0
}

deploy_files() {
	# $1 = install | update
	mode="$1"
	printf '%s\n' "$FILES" | while IFS=':' read -r src dst kind prefix; do
		[ -z "$src" ] && continue

		if [ "$kind" = "config" ]; then
			if [ "$mode" = "update" ]; then
				echo "  skip   $dst (конфиг не трогаем)"
				continue
			fi
			if [ -f "$dst" ]; then
				echo "  keep   $dst"
				continue
			fi
		fi

		echo "  write  $dst"
		tmp="/tmp/agip_dl.$$.$(basename "$dst")"
		if ! fetch "${RAW_BASE}/${src}" "$tmp"; then
			echo "  ! не удалось скачать $src"
			downloader_hint
			rm -f "$tmp"
			exit 1
		fi
		if ! verify_and_install "$tmp" "$dst" "$prefix" "$kind"; then
			echo "  ! обновление прервано, файл $dst не тронут"
			rm -f "$tmp"
			exit 1
		fi
	done
}

save_manifest() {
	printf '%s\n' "$FILES" | while IFS=':' read -r src dst kind prefix; do
		[ "$kind" = "config" ] && continue
		echo "$dst"
	done > "$MARKER"
}

install_manager_locally() {
	local tmp="/tmp/agip_mgr.$$"
	if fetch "$MANAGER_URL" "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
		case "$(head -n 1 "$tmp")" in
			"#!/bin/sh"*)
				mv "$tmp" "$MANAGER_LOCAL"
				chmod 0755 "$MANAGER_LOCAL"
				ln -sf "$MANAGER_LOCAL" /usr/bin/agip
				echo "Менеджер сохранён: команда 'agip' доступна в системе."
				return 0
				;;
		esac
	fi
	rm -f "$tmp"
	echo "Не удалось сохранить локальную копию менеджера (не критично, основной пакет уже установлен)."
}

reload_luci() {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
	/etc/init.d/rpcd restart >/dev/null 2>&1
}

save_version() {
	local ver="$1"
	[ -n "$ver" ] && echo "$ver" > "$VERSION_LOCAL"
}

do_install() {
	banner
	echo "Установка AntiGrayIP..."
	mkdir -p /usr/share/rpcd/acl.d /usr/share/luci/menu.d /www/luci-static/resources/view /etc/hotplug.d/iface
	deploy_files install || { echo "Установка прервана из-за ошибки."; exit 1; }
	save_manifest

	remote_ver="$(fetch_text "${RAW_BASE}/VERSION")"
	save_version "${remote_ver:-$MANAGER_VERSION}"

	/etc/init.d/antigrayip enable
	/etc/init.d/antigrayip restart
	reload_luci
	install_manager_locally
	echo
	echo "Готово. Версия: ${remote_ver:-$MANAGER_VERSION}. LuCI: Службы -> AntiGrayIP."
	echo "Дальше управлять можно командой: agip"
}

do_update() {
	local force="$1"
	banner

	if [ ! -x /etc/init.d/antigrayip ]; then
		echo "AntiGrayIP не установлен, ставлю с нуля."
		do_install
		return
	fi

	local_ver="$( [ -f "$VERSION_LOCAL" ] && cat "$VERSION_LOCAL" || echo "" )"
	remote_ver="$(fetch_text "${RAW_BASE}/VERSION")"

	echo "Установленная версия : ${local_ver:-неизвестно}"
	echo "Доступная версия     : ${remote_ver:-не удалось определить}"

	if [ -n "$remote_ver" ] && [ "$remote_ver" = "$local_ver" ] && [ "$force" != "force" ]; then
		echo "Уже установлена последняя версия. Обновление не требуется."
		echo "Принудительно: agip update force"
		return 0
	fi

	echo "Обновление AntiGrayIP (конфиг и лог не трогаются)..."
	deploy_files update || { echo "Обновление прервано из-за ошибки."; exit 1; }
	save_manifest
	save_version "${remote_ver:-$local_ver}"

	/etc/init.d/antigrayip enable
	/etc/init.d/antigrayip restart
	reload_luci
	install_manager_locally
	echo
	echo "Обновление завершено. Версия: ${remote_ver:-$local_ver}"
}

DEFAULT_SUBNETS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16"

ip2int() {
	oldifs="$IFS"
	IFS=.
	set -- $1
	IFS="$oldifs"
	echo $(( ($1 * 16777216) + ($2 * 65536) + ($3 * 256) + $4 ))
}

in_subnet() {
	# $1 = ip, $2 = cidr
	net="${2%/*}"; bits="${2#*/}"
	case "$bits" in ''|*[!0-9]*) return 1 ;; esac
	[ "$bits" -ge 0 ] && [ "$bits" -le 32 ] || return 1
	ip_int="$(ip2int "$1")"
	net_int="$(ip2int "$net")"
	if [ "$bits" -ge 32 ]; then size=1; else size=$(( 1 << (32 - bits) )); fi
	lo="$net_int"; hi=$(( net_int + size - 1 ))
	[ "$ip_int" -ge "$lo" ] 2>/dev/null && [ "$ip_int" -le "$hi" ] 2>/dev/null
}

# reads antigrayip.settings.gray_subnet (editable list); falls back to the
# built-in defaults if that list is empty, same logic as the daemon.
get_gray_subnets() {
	uci -q get antigrayip.settings.gray_subnet
}

is_private_ip() {
	ip="$1"
	subnets="$(get_gray_subnets)"
	[ -z "$subnets" ] && subnets="$DEFAULT_SUBNETS"
	for s in $subnets; do
		in_subnet "$ip" "$s" && return 0
	done
	return 1
}

do_status() {
	banner
	if [ ! -x /etc/init.d/antigrayip ]; then
		echo "AntiGrayIP не установлен."
		return 0
	fi

	if /etc/init.d/antigrayip enabled 2>/dev/null; then en="да"; else en="нет"; fi
	if pidof antigrayip.sh >/dev/null 2>&1; then run="да"; else run="нет"; fi

	iface="$(uci -q get antigrayip.settings.interface)"
	[ -z "$iface" ] && iface="wan"

	. /lib/functions/network.sh 2>/dev/null

	echo "Версия           : $( [ -f "$VERSION_LOCAL" ] && cat "$VERSION_LOCAL" || echo неизвестно )"
	echo "Автозапуск       : $en"
	echo "Служба запущена  : $run"
	echo "WAN-интерфейсы   :"
	for i in $iface; do
		network_flush_cache 2>/dev/null
		ipaddr=""
		network_get_ipaddr ipaddr "$i" 2>/dev/null
		if [ -n "$ipaddr" ]; then
			if is_private_ip "$ipaddr"; then
				echo "  - $i: $ipaddr (серый/приватный)"
			else
				echo "  - $i: $ipaddr (белый/публичный)"
			fi
		else
			echo "  - $i: <нет адреса>"
		fi
	done

	subnets="$(get_gray_subnets)"
	if [ -z "$subnets" ]; then
		echo "Серые подсети    : (список пуст, используются встроенные по умолчанию)"
	else
		echo "Серые подсети    :"
		for s in $subnets; do
			echo "                   - $s"
		done
	fi

	logf="$(uci -q get antigrayip.settings.log_file)"
	[ -z "$logf" ] && logf="/var/log/antigrayip.log"
	echo "---- последние строки журнала ($logf) ----"
	if [ -f "$logf" ]; then
		tail -n 15 "$logf"
	else
		echo "(журнал ещё не создан)"
	fi
}

do_remove() {
	banner
	purge=0
	for a in "$@"; do
		[ "$a" = "--purge" ] || [ "$a" = "-c" ] && purge=1
	done

	if [ ! -f "$MARKER" ] && [ ! -x /etc/init.d/antigrayip ]; then
		echo "AntiGrayIP не установлен, нечего удалять."
		return 0
	fi

	/etc/init.d/antigrayip stop 2>/dev/null
	/etc/init.d/antigrayip disable 2>/dev/null

	if [ -f "$MARKER" ]; then
		while IFS= read -r f; do
			[ -n "$f" ] && rm -f "$f"
		done < "$MARKER"
		rm -f "$MARKER"
	else
		printf '%s\n' "$FILES" | while IFS=':' read -r src dst kind prefix; do
			[ "$kind" = "config" ] && continue
			rm -f "$dst"
		done
	fi

	rm -f "$VERSION_LOCAL"
	reload_luci

	if [ "$purge" = "1" ]; then
		rm -f /etc/config/antigrayip /var/log/antigrayip.log
		echo "AntiGrayIP удалён полностью, включая конфиг и лог."
	else
		echo "AntiGrayIP удалён. Конфиг /etc/config/antigrayip и лог оставлены."
		echo "Для полного удаления: agip purge"
	fi
}

show_menu() {
	banner
	echo "1) Установить / переустановить"
	echo "2) Обновить"
	echo "3) Статус"
	echo "4) Удалить"
	echo "5) Удалить полностью (с конфигом и логом)"
	echo "0) Выход"
	printf '%s' "Выбор [0-5]: "
	read -r choice
	case "$choice" in
		1) do_install ;;
		2) do_update ;;
		3) do_status ;;
		4) do_remove ;;
		5) do_remove --purge ;;
		0) exit 0 ;;
		*) echo "Неверный выбор."; exit 1 ;;
	esac
}

ACTION="$1"
case "$ACTION" in
	install)          do_install ;;
	update)            shift; do_update "$@" ;;
	status)            do_status ;;
	remove|uninstall)  shift; do_remove "$@" ;;
	purge)             do_remove --purge ;;
	""|menu)           show_menu ;;
	*)
		echo "Использование: $0 [install|update [force]|status|remove|purge]"
		exit 1
		;;
esac
