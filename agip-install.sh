#!/bin/sh
# agip-install.sh - быстрая установка AntiGrayIP.
# Скачивает AGIP-Manager.sh и запускает его с действием "install".
#
#   sh <(wget -qO - 'https://raw.githubusercontent.com/LexYea/AntiGrayIP/main/agip-install.sh')
#
# by LexYea | aedev.ru

set -e

RAW_BASE="https://raw.githubusercontent.com/LexYea/AntiGrayIP/main"
TMP="/tmp/agip-manager.$$.sh"

fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1" -o "$2"
	else
		wget -qO "$2" "$1"
	fi
}

if ! fetch "${RAW_BASE}/AGIP-Manager.sh" "$TMP"; then
	echo "Не удалось скачать AGIP-Manager.sh."
	if command -v apk >/dev/null 2>&1; then
		echo "Проверьте HTTPS-поддержку: apk update && apk add wget curl"
	else
		echo "Проверьте HTTPS-поддержку: opkg update && opkg install wget-ssl"
	fi
	rm -f "$TMP"
	exit 1
fi

sh "$TMP" install "$@"
rm -f "$TMP"
