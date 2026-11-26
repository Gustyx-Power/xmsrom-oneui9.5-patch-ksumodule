#!/system/bin/sh
MODDIR="${0%/*}"
STATE_DIR="/data/adb/xmsrom_thermal_fix"
LOG="$STATE_DIR/thermal.log"
TARGET_DIR="/system/priv-app/DigitalKey"

mkdir -p "$STATE_DIR"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.prev"
log() { printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo 'boot')" "$*" >> "$LOG"; }

if [ -d "$TARGET_DIR" ]; then
  if mount -t tmpfs -o mode=755,uid=0,gid=0 xmsrom_dkey_mask "$TARGET_DIR"; then
    chcon u:object_r:system_file:s0 "$TARGET_DIR" 2>/dev/null || true
    mount -o remount,ro "$TARGET_DIR" 2>/dev/null || true
    log "masked $TARGET_DIR via ro tmpfs"
  else
    log "WARN: tmpfs mask failed on $TARGET_DIR; will rely on pm disable in service.sh"
  fi
else
  log "info: $TARGET_DIR not present"
fi
