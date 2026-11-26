#!/system/bin/sh
export PATH="/system/bin:/system/xbin:/data/adb/ksu/bin:$PATH"
STATE_DIR="/data/adb/xmsrom_thermal_fix"
LOG="$STATE_DIR/thermal.log"
PKG="com.samsung.android.dkey"

log() { printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo 'svc')" "$*" >> "$LOG"; }
(
  i=0
  while [ "$i" -lt 120 ]; do
    if [ "$(getprop sys.boot_completed)" = "1" ] && pm path android >/dev/null 2>&1; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if pm path "$PKG" >/dev/null 2>&1; then
    if ! pm list packages -d 2>/dev/null | grep -qx "package:$PKG"; then
      pm disable-user --user 0 "$PKG" >/dev/null 2>&1 || pm disable "$PKG" >/dev/null 2>&1 || true
      am force-stop "$PKG" >/dev/null 2>&1 || true
      log "disabled fallback package $PKG"
    else
      log "$PKG already disabled"
    fi
  else
    log "OK: $PKG not exposed to PackageManager"
  fi
) >/dev/null 2>&1 &
