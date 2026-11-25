#!/system/bin/sh
SKIPUNZIP=0

STATE_DIR="/data/adb/xmsrom_addons"
OLD_MOD="/data/adb/modules/$MODID"

ui_print "*********************************************"
ui_print "   XMSROM OneUI 9.5 Modular Add-ons (KSU)    "
ui_print "   Maintainer: GustyxPower                   "
ui_print "*********************************************"

mkdir -p "$STATE_DIR/installed" "$STATE_DIR/tmp" "$MODPATH/system"

# Preserve already-downloaded add-ons when upgrading module ZIP
if [ -d "$OLD_MOD/system" ]; then
  if [ -n "$(find "$OLD_MOD/system" -mindepth 1 2>/dev/null | head -n 1)" ]; then
    ui_print "- Preserving previously installed OneUI packs..."
    cp -af "$OLD_MOD/system/." "$MODPATH/system/"
  fi
fi

# Detect mount strategy for user visibility
if [ -e /dev/nomount ] || [ -e /proc/nomount ] || [ -d /sys/fs/nomount ] || grep -qi 'nomount' /proc/kallsyms 2>/dev/null; then
  ui_print "- Kernel NoMount detected: VFS path redirect ready"
elif [ -d /data/adb/metamodule ] && [ ! -f /data/adb/metamodule/disable ]; then
  ui_print "- External KernelSU metamodule detected"
else
  ui_print "- Standard kernel detected: using built-in Magic Mount (/data -> /system)"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Open WebUI inside KernelSU Next Manager to download packs"
