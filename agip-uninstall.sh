#!/bin/sh
# agip-uninstall.sh - самостоятельное удаление AntiGrayIP.
# Не зависит от AGIP-Manager.sh и не требует интернета.
#
#   sh agip-uninstall.sh            # конфиг и лог остаются
#   sh agip-uninstall.sh --purge    # удалить всё, включая конфиг и лог
#
# by LexYea | aedev.ru

set -e

purge=0
[ "$1" = "--purge" ] || [ "$1" = "-c" ] && purge=1

/etc/init.d/antigrayip stop 2>/dev/null || true
/etc/init.d/antigrayip disable 2>/dev/null || true

rm -f /usr/bin/antigrayip.sh
rm -f /etc/init.d/antigrayip
rm -f /etc/hotplug.d/iface/95-antigrayip
rm -f /usr/share/rpcd/acl.d/luci-app-antigrayip.json
rm -f /usr/share/luci/menu.d/luci-mod-antigrayip.json
rm -f /www/luci-static/resources/view/antigrayip.js
rm -f /usr/lib/antigrayip.version
rm -f /usr/lib/antigrayip.files
rm -f /usr/bin/agip-manager.sh /usr/bin/agip

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

if [ "$purge" = "1" ]; then
	rm -f /etc/config/antigrayip /var/log/antigrayip.log
	echo "AntiGrayIP удалён полностью, включая конфиг и лог."
else
	echo "AntiGrayIP удалён. Конфиг /etc/config/antigrayip и лог оставлены."
	echo "Для полного удаления: sh agip-uninstall.sh --purge"
fi
