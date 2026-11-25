#!/system/bin/sh
STATE_DIR="/data/adb/xmsrom_selinux"
GUARD="$STATE_DIR/boot_guard"
LOG="$STATE_DIR/boot.log"
MODE_FILE="$STATE_DIR/mode"
STAGE_FILE="$STATE_DIR/stage"

log() { printf '%s %s\n' "$(date +%H:%M:%S 2>/dev/null || echo 'svc')" "$*" >> "$LOG"; }

(
  i=0
  while [ "$i" -lt 120 ]; do
    if [ "$(getprop sys.boot_completed)" = "1" ] && pm path android >/dev/null 2>&1; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  sleep 3

  mode="enforcing"
  [ -f "$MODE_FILE" ] && mode="$(tr -d ' \r\n' < "$MODE_FILE" 2>/dev/null)"
  stage="service"
  [ -f "$STAGE_FILE" ] && stage="$(tr -d ' \r\n' < "$STAGE_FILE" 2>/dev/null)"

  if [ "$mode" != "permissive" ] && [ "$stage" != "early" ]; then
    date +%s > "$GUARD" 2>/dev/null || echo "armed" > "$GUARD"
    sync
    if setenforce 1 2>/dev/null || printf '1' > /sys/fs/selinux/enforce 2>/dev/null; then
      log "stage=service setenforce 1 ok -> now=$(getenforce 2>/dev/null)"
    else
      rm -f "$GUARD"
      log "ERROR: stage=service setenforce 1 rejected"
    fi
    sleep 3
  fi

  if [ "$(getprop sys.boot_completed)" = "1" ] && pgrep -f com.android.systemui >/dev/null 2>&1; then
    rm -f "$GUARD"
    log "BOOT_OK: SystemUI healthy, guard cleared (enforce=$(getenforce 2>/dev/null))"
  else
    log "WARN: SystemUI or boot_completed check incomplete (enforce=$(getenforce 2>/dev/null)); guard kept"
  fi
) >/dev/null 2>&1 &
