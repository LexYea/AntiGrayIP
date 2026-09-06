#!/bin/sh
# agip-install.sh - самостоятельная офлайн-установка AntiGrayIP.
# Не зависит от AGIP-Manager.sh и не требует интернета на роутере.
#
# Запускать из папки пакета, где рядом лежит директория files/:
#
#   scp -r AntiGrayIP root@192.168.1.1:/tmp/
#   ssh root@192.168.1.1 "sh /tmp/AntiGrayIP/agip-install.sh"
#
# by LexYea | aedev.ru

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/files"

if [ ! -d "$SRC" ]; then
	echo "Не найдена папка $SRC."
	echo "Запустите этот скрипт из папки пакета AntiGrayIP (рядом с ним должна быть files/)."
	exit 1
fi

copy() {
	# $1 = путь относительно files/   $2 = куда положить   $3 = права
	mkdir -p "$(dirname "$2")"
	cp "$SRC/$1" "$2"
	chmod "$3" "$2"
	echo "  write  $2"
}

echo "Установка AntiGrayIP..."

if [ -f /etc/config/antigrayip ]; then
	echo "  keep   /etc/config/antigrayip"
else
	copy etc/config/antigrayip /etc/config/antigrayip 0644
fi

copy usr/bin/antigrayip.sh                          /usr/bin/antigrayip.sh                          0755
copy etc/init.d/antigrayip                          /etc/init.d/antigrayip                          0755
copy etc/hotplug.d/iface/95-antigrayip               /etc/hotplug.d/iface/95-antigrayip               0755
copy usr/share/rpcd/acl.d/luci-app-antigrayip.json   /usr/share/rpcd/acl.d/luci-app-antigrayip.json   0644
copy usr/share/luci/menu.d/luci-mod-antigrayip.json  /usr/share/luci/menu.d/luci-mod-antigrayip.json  0644
copy www/luci-static/resources/view/antigrayip.js    /www/luci-static/resources/view/antigrayip.js    0644

[ -f "$SCRIPT_DIR/VERSION" ] && cp "$SCRIPT_DIR/VERSION" /usr/lib/antigrayip.version

/etc/init.d/antigrayip enable
/etc/init.d/antigrayip restart

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

# необязательно: если рядом лежит AGIP-Manager.sh, сохраняем его как 'agip'
# для дальнейшего управления (обновление через интернет, статус и т.д.) -
# отсутствие этого файла ни на что не влияет, установка не зависит от него.
if [ -f "$SCRIPT_DIR/AGIP-Manager.sh" ]; then
	cp "$SCRIPT_DIR/AGIP-Manager.sh" /usr/bin/agip-manager.sh
	chmod 0755 /usr/bin/agip-manager.sh
	ln -sf /usr/bin/agip-manager.sh /usr/bin/agip
	echo "Менеджер сохранён: команда 'agip' доступна в системе (для update/status через интернет)."
fi

echo
echo "Готово. LuCI: Службы -> AntiGrayIP."
