#!/system/bin/sh
MODDIR="${0%/*}"
STATE_DIR="/data/adb/xmsrom_addons"
mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/reboot_pending"
# Clear any stale download job left from an interrupted pre-reboot session
if [ -f "$STATE_DIR/job.pid" ]; then
  old_pid="$(cat "$STATE_DIR/job.pid" 2>/dev/null)"
  if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
    rm -f "$STATE_DIR/job.pid" "$STATE_DIR/job.json"
  fi
elif [ -f "$STATE_DIR/job.json" ]; then
  rm -f "$STATE_DIR/job.json"
fi

# Post-boot fixes for BixbyWakeup (avoid QTI taro SoundTrigger crash loop) and Quick Share / Smart View runtime permissions
need_qs=0
if [ -d "$MODDIR/system/app/MdxKitService" ] || [ -d "$MODDIR/system/app/SmartMirroring" ]; then
  need_qs=1
fi
need_wakeup=0
[ -d "$MODDIR/system/app/BixbyWakeup" ] && need_wakeup=1

if [ "$need_qs" -eq 1 ] || [ "$need_wakeup" -eq 1 ]; then
  (
    i=0
    while [ "$i" -lt 60 ]; do
      [ "$(getprop sys.boot_completed)" = "1" ] && [ -d /data/system/users/0 ] && break
      sleep 1
      i=$((i + 1))
    done
    sleep 2

    if [ "$need_wakeup" -eq 1 ] && pm path com.samsung.android.bixby.wakeup >/dev/null 2>&1; then
      for cmp in \
        com.samsung.android.bixby.wakeup/com.samsung.android.env.PersistentService \
        com.samsung.android.bixby.wakeup/com.samsung.android.voicewakeup.soundtrigger.DspControlService; do
        pm disable "$cmp" >/dev/null 2>&1 || true
      done
      prefs="/data/data/com.samsung.android.bixby.wakeup/shared_prefs/com.samsung.android.bixby.wakeup_preferences.xml"
      if [ -f "$prefs" ]; then
        if grep -qE 'name="(gesture_wakeup_enabled|voice_wake_up)" value="true"' "$prefs" 2>/dev/null; then
          sed -i 's/name="gesture_wakeup_enabled" value="true"/name="gesture_wakeup_enabled" value="false"/; s/name="voice_wake_up" value="true"/name="voice_wake_up" value="false"/' "$prefs" 2>/dev/null || true
          chown system:system "$prefs" 2>/dev/null || true
          chmod 0660 "$prefs" 2>/dev/null || true
          chcon u:object_r:system_app_data_file:s0 "$prefs" 2>/dev/null || true
          am force-stop com.samsung.android.bixby.wakeup >/dev/null 2>&1 || true
        fi
      elif [ -d /data/data/com.samsung.android.bixby.wakeup ]; then
        mkdir -p /data/data/com.samsung.android.bixby.wakeup/shared_prefs
        chown system:system /data/data/com.samsung.android.bixby.wakeup/shared_prefs 2>/dev/null || true
        chmod 0771 /data/data/com.samsung.android.bixby.wakeup/shared_prefs 2>/dev/null || true
        chcon u:object_r:system_app_data_file:s0 /data/data/com.samsung.android.bixby.wakeup/shared_prefs 2>/dev/null || true
        printf "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n    <boolean name=\"gesture_wakeup_enabled\" value=\"false\" />\n    <boolean name=\"voice_wake_up\" value=\"false\" />\n</map>\n" > "$prefs"
        chown system:system "$prefs" 2>/dev/null || true
        chmod 0660 "$prefs" 2>/dev/null || true
        chcon u:object_r:system_app_data_file:s0 "$prefs" 2>/dev/null || true
        am force-stop com.samsung.android.bixby.wakeup >/dev/null 2>&1 || true
      fi
    fi

    need_grant=0
    if [ "$need_qs" -eq 1 ]; then
      for p in com.samsung.android.mdx.kit com.samsung.android.mcfds com.samsung.android.smartmirroring; do
        if pm path "$p" >/dev/null 2>&1 && ! dumpsys package "$p" | grep -q "BLUETOOTH_CONNECT: granted=true"; then
          need_grant=1
          break
        fi
      done
    fi

    if [ "$need_grant" -eq 1 ]; then
      grant_perms() {
        pkg="$1"; shift
        pm path "$pkg" >/dev/null 2>&1 || return 0
        for perm in "$@"; do
          pm grant --user 0 "$pkg" "$perm" >/dev/null 2>&1 || true
        done
      }

      grant_perms com.samsung.android.mdx.kit \
        android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_CONNECT \
        android.permission.BLUETOOTH_ADVERTISE android.permission.NEARBY_WIFI_DEVICES \
        android.permission.ACCESS_LOCAL_NETWORK

      grant_perms com.samsung.android.mcfds \
        android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_BACKGROUND_LOCATION \
        android.permission.ACCESS_COARSE_LOCATION android.permission.ACCESS_LOCAL_NETWORK \
        android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_CONNECT \
        android.permission.BLUETOOTH_ADVERTISE android.permission.NEARBY_WIFI_DEVICES \
        android.permission.UWB_RANGING android.permission.RANGING \
        android.permission.POST_NOTIFICATIONS

      grant_perms com.samsung.android.mcfserver \
        android.permission.READ_CONTACTS android.permission.ACCESS_COARSE_LOCATION \
        android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_CONNECT \
        android.permission.BLUETOOTH_ADVERTISE android.permission.NEARBY_WIFI_DEVICES \
        android.permission.UWB_RANGING

      grant_perms com.samsung.android.beaconmanager \
        android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_BACKGROUND_LOCATION \
        android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_ADVERTISE \
        android.permission.BLUETOOTH_CONNECT android.permission.POST_NOTIFICATIONS

      grant_perms com.samsung.android.aware.service \
        android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_BACKGROUND_LOCATION \
        android.permission.READ_CONTACTS android.permission.READ_EXTERNAL_STORAGE \
        android.permission.READ_MEDIA_IMAGES android.permission.READ_MEDIA_AUDIO \
        android.permission.READ_MEDIA_VIDEO android.permission.WRITE_EXTERNAL_STORAGE \
        android.permission.ACCESS_MEDIA_LOCATION android.permission.NEARBY_WIFI_DEVICES \
        android.permission.ACCESS_LOCAL_NETWORK android.permission.POST_NOTIFICATIONS

      grant_perms com.samsung.android.allshare.service.mediashare \
        android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_BACKGROUND_LOCATION \
        android.permission.NEARBY_WIFI_DEVICES android.permission.WRITE_EXTERNAL_STORAGE

      grant_perms com.samsung.android.smartmirroring \
        android.permission.NEARBY_WIFI_DEVICES android.permission.ACCESS_FINE_LOCATION \
        android.permission.BLUETOOTH_ADVERTISE android.permission.BLUETOOTH_CONNECT \
        android.permission.BLUETOOTH_SCAN android.permission.POST_NOTIFICATIONS
    fi
  ) >/dev/null 2>&1 &
fi
