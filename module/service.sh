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

# Auto-grant runtime permissions required by newly mounted Quick Share / Smart View system packages on existing /data
if [ -d "$MODDIR/system/app/MdxKitService" ] || [ -d "$MODDIR/system/app/SmartMirroring" ]; then
  (
    i=0
    while [ "$i" -lt 60 ]; do
      [ "$(getprop sys.boot_completed)" = "1" ] && [ -d /data/system/users/0 ] && break
      sleep 1
      i=$((i + 1))
    done
    sleep 2

    need_grant=0
    for p in com.samsung.android.mdx.kit com.samsung.android.mcfds com.samsung.android.smartmirroring; do
      if pm path "$p" >/dev/null 2>&1 && ! dumpsys package "$p" | grep -q "BLUETOOTH_CONNECT: granted=true"; then
        need_grant=1
        break
      fi
    done

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
