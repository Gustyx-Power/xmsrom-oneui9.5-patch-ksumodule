#!/system/bin/sh
MODDIR="${0%/*}"
STATE_DIR="/data/adb/xmsrom_addons"

echo "XMSROM OneUI 9.5 Add-ons Status"
echo "================================"
echo "Mount Engine : $(cat "$STATE_DIR/active_engine" 2>/dev/null || echo 'not_mounted')"
echo "Data Free    : $(df -h /data | awk 'NR==2{print $4" / "$2}')"
echo "Installed    :"
if [ -d "$STATE_DIR/installed" ] && [ -n "$(ls -A "$STATE_DIR/installed" 2>/dev/null)" ]; then
  for f in "$STATE_DIR/installed"/*.list; do
    [ -f "$f" ] || continue
    name="${f##*/}"
    echo "  - ${name%.list}"
  done
else
  echo "  (none yet - open WebUI to install packs)"
fi
echo ""
echo "Recent Mount Log:"
tail -n 10 "$STATE_DIR/mount.log" 2>/dev/null || echo "  (empty)"
