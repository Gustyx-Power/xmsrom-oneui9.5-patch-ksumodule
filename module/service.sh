#!/system/bin/sh
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
