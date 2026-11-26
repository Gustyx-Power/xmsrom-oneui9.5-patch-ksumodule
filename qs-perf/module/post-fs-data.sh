#!/system/bin/sh
MODDIR="${0%/*}"
STATE_DIR="/data/adb/xmsrom_qs_perf"
GUARD="$STATE_DIR/boot_guard"
MODE_FILE="$STATE_DIR/sysui_mode"
LOG="$STATE_DIR/boot.log"
RP="/data/adb/ksu/bin/resetprop"
TARGET_DIR="/system/system_ext/priv-app/SystemUI"
MOD_DIR="$MODDIR/system/system_ext/priv-app/SystemUI"
PATCHED_APK="$MOD_DIR/SystemUI.apk"
PATCHED_ODEX="$MOD_DIR/oat/arm64/SystemUI.odex"
PATCHED_VDEX="$MOD_DIR/oat/arm64/SystemUI.vdex"
PATCH_VER="$(cat "$MODDIR/sysui_ver" 2>/dev/null || echo phase2_v3)"

mkdir -p "$STATE_DIR"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.prev"
log() { printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo 'boot')" "$*" >> "$LOG"; }

if [ -f "$GUARD" ]; then
  rm -f "$GUARD"
  touch "$MODDIR/disable"
  rm -f /data/dalvik-cache/arm64/*SystemUI* /data/misc/apexdata/com.android.art/dalvik-cache/arm64/*SystemUI* 2>/dev/null
  echo "stock" > "$MODE_FILE"
  log "ROLLBACK: previous boot did not clear guard; disabling xmsrom_qs_perf & cleared SystemUI dalvik-cache"
  exit 0
fi

date +%s > "$GUARD" 2>/dev/null || echo 1 > "$GUARD"
sync

"$RP" -n debug.sf.disable_client_composition_cache 0
"$RP" -n debug.sf.enable_layer_caching 1
"$RP" -n debug.sf.enable_planner_prediction 1
"$RP" -n debug.sf.predict_hwc_composition_strategy 1
"$RP" -n debug.renderengine.kawase2_off_critical_path true
"$RP" -n debug.sf.set_idle_timer_ms 1000
"$RP" -n ro.surface_flinger.use_content_detection_for_refresh_rate false
log "applied Phase 1 SF props cleanly"

if [ -s "$PATCHED_APK" ]; then
  CUR_MODE="$(cat "$MODE_FILE" 2>/dev/null || echo stock)"
  if [ "$CUR_MODE" != "$PATCH_VER" ]; then
    rm -f /data/dalvik-cache/arm64/*SystemUI* /data/misc/apexdata/com.android.art/dalvik-cache/arm64/*SystemUI* 2>/dev/null
    log "cleared stale SystemUI dalvik-cache ($CUR_MODE -> $PATCH_VER)"
  fi
  chown 0:0 "$PATCHED_APK"
  chmod 0644 "$PATCHED_APK"
  chcon u:object_r:system_file:s0 "$PATCHED_APK" 2>/dev/null || true

  if mount -t tmpfs -o mode=755,uid=0,gid=0 xmsrom_qs_magic "$TARGET_DIR"; then
    chcon u:object_r:system_file:s0 "$TARGET_DIR" 2>/dev/null || true
    : > "$TARGET_DIR/SystemUI.apk"
    chmod 0644 "$TARGET_DIR/SystemUI.apk"
    chcon u:object_r:system_file:s0 "$TARGET_DIR/SystemUI.apk" 2>/dev/null || true
    if mount -o bind "$PATCHED_APK" "$TARGET_DIR/SystemUI.apk"; then
      chcon u:object_r:system_file:s0 "$TARGET_DIR/SystemUI.apk" 2>/dev/null || true
      OAT_OK="no-oat"
      if [ -s "$PATCHED_ODEX" ] && [ -s "$PATCHED_VDEX" ]; then
        mkdir -p "$TARGET_DIR/oat/arm64"
        chown -R 0:0 "$TARGET_DIR/oat" "$PATCHED_ODEX" "$PATCHED_VDEX"
        chmod 0755 "$TARGET_DIR/oat" "$TARGET_DIR/oat/arm64"
        chmod 0644 "$PATCHED_ODEX" "$PATCHED_VDEX"
        chcon u:object_r:system_file:s0 "$TARGET_DIR/oat" "$TARGET_DIR/oat/arm64" "$PATCHED_ODEX" "$PATCHED_VDEX" 2>/dev/null || true
        : > "$TARGET_DIR/oat/arm64/SystemUI.odex"
        : > "$TARGET_DIR/oat/arm64/SystemUI.vdex"
        chmod 0644 "$TARGET_DIR/oat/arm64/SystemUI.odex" "$TARGET_DIR/oat/arm64/SystemUI.vdex"
        chcon u:object_r:system_file:s0 "$TARGET_DIR/oat/arm64/SystemUI.odex" "$TARGET_DIR/oat/arm64/SystemUI.vdex" 2>/dev/null || true
        if mount -o bind "$PATCHED_ODEX" "$TARGET_DIR/oat/arm64/SystemUI.odex" && mount -o bind "$PATCHED_VDEX" "$TARGET_DIR/oat/arm64/SystemUI.vdex"; then
          chcon u:object_r:system_file:s0 "$TARGET_DIR/oat/arm64/SystemUI.odex" "$TARGET_DIR/oat/arm64/SystemUI.vdex" 2>/dev/null || true
          OAT_OK="speed-oat"
        else
          rm -rf "$TARGET_DIR/oat"
          OAT_OK="oat-bind-failed"
        fi
      fi
      mount -o remount,ro "$TARGET_DIR" 2>/dev/null || true
      echo "$PATCH_VER" > "$MODE_FILE"
      log "mounted patched SystemUI.apk ($PATCH_VER, $OAT_OK)"
    else
      umount "$TARGET_DIR" 2>/dev/null || true
      echo "stock" > "$MODE_FILE"
      log "ERROR: bind-mount SystemUI.apk failed; reverted tmpfs"
    fi
  else
    log "ERROR: tmpfs mount on $TARGET_DIR failed"
  fi
else
  log "WARN: patched SystemUI.apk missing; skipping mount"
fi
