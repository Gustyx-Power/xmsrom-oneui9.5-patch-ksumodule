#!/system/bin/sh
SKIPUNZIP=0
STATE_DIR="/data/adb/xmsrom_selinux"

ui_print "*********************************************"
ui_print "   XMSROM SELinux Enforcing Guard (KSU)      "
ui_print "   Maintainer: GustyxPower                   "
ui_print "*********************************************"

mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/boot_guard"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
if [ -f "$MODPATH/system/system_ext/etc/selinux/system_ext_seapp_contexts" ]; then
  chcon u:object_r:seapp_contexts_file:s0 "$MODPATH/system/system_ext/etc/selinux/system_ext_seapp_contexts" 2>/dev/null || true
fi

ui_print "- Anti-bootloop guard resets automatically if a boot stalls"
ui_print "- Reboot to enter real SELinux Enforcing"
