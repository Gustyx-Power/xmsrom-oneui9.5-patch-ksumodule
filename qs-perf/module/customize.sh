#!/system/bin/sh
SKIPUNZIP=0
STATE_DIR="/data/adb/xmsrom_qs_perf"

ui_print "*********************************************"
ui_print "   XMSROM QS Smoothness Tuning v2.1.0 (KSU)  "
ui_print "   Maintainer: GustyxPower                   "
ui_print "*********************************************"

mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/boot_guard"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Anti-bootloop guard resets automatically if SystemUI stalls"
ui_print "- Reboot to activate updated SystemUI & SurfaceFlinger tuning"
