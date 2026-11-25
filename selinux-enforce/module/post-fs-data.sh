#!/system/bin/sh
MODDIR="${0%/*}"
STATE_DIR="/data/adb/xmsrom_selinux"
LOG="$STATE_DIR/boot.log"
GUARD="$STATE_DIR/boot_guard"
MODE_FILE="$STATE_DIR/mode"
STAGE_FILE="$STATE_DIR/stage"

mkdir -p "$STATE_DIR"
log() { printf '%s %s\n' "$(date +%H:%M:%S 2>/dev/null || echo 'boot')" "$*" >> "$LOG"; }

[ -f "$LOG" ] && mv -f "$LOG" "$LOG.prev"
log "post-fs-data start (cur=$(getenforce 2>/dev/null))"

# Anti-bootloop deadman guard: if previous enforcing boot never cleared guard, disable module safely
if [ -f "$GUARD" ]; then
  rm -f "$GUARD"
  touch "$MODDIR/disable"
  log "ROLLBACK: previous enforcing boot did not reach healthy desktop; module auto-disabled, staying Permissive"
  exit 0
fi

BB=""
for p in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
  [ -x "$p" ] && BB="$p" && break
done

# Bind-mount patched system_ext_seapp_contexts BEFORE zygote starts
SRC_SEAPP="$MODDIR/system/system_ext/etc/selinux/system_ext_seapp_contexts"
DST_SEAPP="/system/system_ext/etc/selinux/system_ext_seapp_contexts"
if [ -f "$SRC_SEAPP" ] && [ -f "$DST_SEAPP" ]; then
  chmod 0644 "$SRC_SEAPP" 2>/dev/null
  chcon u:object_r:seapp_contexts_file:s0 "$SRC_SEAPP" 2>/dev/null
  if [ -n "$BB" ] && "$BB" mount --bind "$SRC_SEAPP" "$DST_SEAPP"; then
    "$BB" mount --make-private "$DST_SEAPP" 2>/dev/null
    log "mounted system_ext_seapp_contexts via $BB"
  elif mount -o bind "$SRC_SEAPP" "$DST_SEAPP"; then
    log "mounted system_ext_seapp_contexts via mount"
  else
    log "ERROR: failed to bind-mount system_ext_seapp_contexts"
    exit 0
  fi
fi

mode="enforcing"
[ -f "$MODE_FILE" ] && mode="$(tr -d ' \r\n' < "$MODE_FILE" 2>/dev/null)"
stage="service"
[ -f "$STAGE_FILE" ] && stage="$(tr -d ' \r\n' < "$STAGE_FILE" 2>/dev/null)"

if [ "$mode" = "permissive" ]; then
  log "mode=permissive (audit-only): contexts & sepolicy.rule active, leaving Permissive"
  exit 0
fi

if [ "$stage" = "early" ]; then
  date +%s > "$GUARD" 2>/dev/null || echo "armed" > "$GUARD"
  sync
  if setenforce 1 2>/dev/null || printf '1' > /sys/fs/selinux/enforce 2>/dev/null; then
    log "stage=early setenforce 1 ok -> now=$(getenforce 2>/dev/null)"
  else
    rm -f "$GUARD"
    log "ERROR: stage=early setenforce 1 rejected"
  fi
else
  log "stage=$stage: contexts & sepolicy.rule ready; service.sh will enforce after boot_completed"
fi
