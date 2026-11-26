#!/system/bin/sh
SKIPUNZIP=0
STATE_DIR="/data/adb/xmsrom_thermal_fix"

ui_print "*********************************************"
ui_print "   XMSROM Daily Thermal Fix (KSU)            "
ui_print "   Maintainer: GustyxPower                   "
ui_print "*********************************************"

mkdir -p "$STATE_DIR"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Masks /system/priv-app/DigitalKey via ro tmpfs at boot"
ui_print "- Reboot required for DigitalKey mask to take effect"
