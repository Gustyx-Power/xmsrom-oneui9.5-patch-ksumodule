#!/system/bin/sh
# Backend controller invoked by KernelSU WebUI or root shell
PATH="/data/adb/ksu/bin:/system/bin:/vendor/bin:$PATH"

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/*}"
STATE_DIR="/data/adb/xmsrom_addons"
INST_DIR="$STATE_DIR/installed"
TMP_DIR="$STATE_DIR/tmp"
JOB_FILE="$STATE_DIR/job.json"
PID_FILE="$STATE_DIR/job.pid"
JOB_LOG="$STATE_DIR/job.log"
MIRROR_FILE="$STATE_DIR/mirror.conf"
MODE_FILE="$STATE_DIR/mount_mode"
CATALOG_CACHE="$STATE_DIR/catalog_cache.json"

mkdir -p "$STATE_DIR" "$INST_DIR" "$TMP_DIR" "$MODDIR/system"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

write_job() {
  st="$1"
  pk="$2"
  pct="$3"
  dl="$4"
  tot="$5"
  msg="$6"
  cat > "$JOB_FILE.tmp" <<EOF
{"state":"$(json_escape "$st")","pack":"$(json_escape "$pk")","percent":$pct,"downloaded":$dl,"total":$tot,"message":"$(json_escape "$msg")"}
EOF
  mv -f "$JOB_FILE.tmp" "$JOB_FILE"
}

validate_id() {
  printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]{1,48}$'
}

validate_sha() {
  [ "$1" = "skip" ] || printf '%s' "$1" | grep -Eq '^[a-fA-F0-9]{64}$'
}

validate_https_url() {
  case "$1" in
    https://*)
      ! printf '%s' "$1" | grep -Eq '[[:space:]"'\''`$;|&<>]'
      ;;
    *) return 1 ;;
  esac
}

cmd_status() {
  engine="$(cat "$STATE_DIR/active_engine" 2>/dev/null | tr -d '\r\n')"
  [ -z "$engine" ] && engine="idle"

  has_nomount=0
  if [ -e /dev/nomount ] || [ -e /proc/nomount ] || [ -d /sys/fs/nomount ] || grep -qi 'nomount' /proc/kallsyms 2>/dev/null; then
    has_nomount=1
  fi

  has_meta=0
  [ -d /data/adb/metamodule ] && [ ! -f /data/adb/metamodule/disable ] && has_meta=1

  mount_override="$(cat "$MODE_FILE" 2>/dev/null | tr -d '\r\n ')"
  [ -z "$mount_override" ] && mount_override="auto"

  df_data="$(df -k /data 2>/dev/null | awk 'NR==2{print $2" "$4}')"
  data_total_kb="$(printf '%s' "$df_data" | awk '{print $1}')"
  data_free_kb="$(printf '%s' "$df_data" | awk '{print $2}')"
  [ -z "$data_total_kb" ] && data_total_kb=0
  [ -z "$data_free_kb" ] && data_free_kb=0

  sys_free_kb="$(df -k / 2>/dev/null | awk 'NR==2{print $4}')"
  [ -z "$sys_free_kb" ] && sys_free_kb=0

  staged_kb="$(du -sk "$MODDIR/system" 2>/dev/null | awk '{print $1}')"
  [ -z "$staged_kb" ] && staged_kb=0

  mirror="$(cat "$MIRROR_FILE" 2>/dev/null | tr -d '\r\n')"

  reboot_pending=0
  [ -f "$STATE_DIR/reboot_pending" ] && reboot_pending=1

  # Check whether background job is genuinely running
  if [ -f "$PID_FILE" ]; then
    jp="$(cat "$PID_FILE" 2>/dev/null)"
    if [ -n "$jp" ] && ! kill -0 "$jp" 2>/dev/null; then
      rm -f "$PID_FILE"
    fi
  fi

  installed_json="["
  first=1
  for f in "$INST_DIR"/*.list; do
    [ -f "$f" ] || continue
    nm="${f##*/}"
    id="${nm%.list}"
    [ "$first" = "1" ] && first=0 || installed_json="$installed_json,"
    installed_json="$installed_json\"$(json_escape "$id")\""
  done
  installed_json="$installed_json]"

  if [ -f "$JOB_FILE" ]; then
    job_json="$(cat "$JOB_FILE" 2>/dev/null)"
  else
    job_json='{"state":"idle","pack":"","percent":0,"downloaded":0,"total":0,"message":""}'
  fi

  cat <<EOF
{"moddir":"$(json_escape "$MODDIR")","mount_engine":"$(json_escape "$engine")","has_nomount":$has_nomount,"has_metamodule":$has_meta,"mount_override":"$(json_escape "$mount_override")","data_free_kb":$data_free_kb,"data_total_kb":$data_total_kb,"system_free_kb":$sys_free_kb,"staged_kb":$staged_kb,"mirror_url":"$(json_escape "$mirror")","reboot_pending":$reboot_pending,"installed":$installed_json,"job":$job_json}
EOF
}

cmd_get_catalog() {
  if [ -f "$CATALOG_CACHE" ] && grep -q '"packs"' "$CATALOG_CACHE" 2>/dev/null; then
    cat "$CATALOG_CACHE"
  elif [ -f "$MODDIR/catalog.json" ]; then
    cat "$MODDIR/catalog.json"
  else
    echo '{"version":"0","packs":[]}'
  fi
}

cmd_fetch_catalog() {
  url="$1"
  validate_https_url "$url" || { echo "invalid catalog url" >&2; return 1; }
  tmp="$TMP_DIR/catalog.json.tmp"
  if curl -fsSL --connect-timeout 10 --max-time 25 "$url" -o "$tmp" && grep -q '"packs"' "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$CATALOG_CACHE"
    cat "$CATALOG_CACHE"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

unpack_verified_archive() {
  id="$1"
  archive="$2"
  expected_sha="$3"
  expected_bytes="$4"

  write_job "verifying" "$id" 92 "$expected_bytes" "$expected_bytes" "Verifying SHA-256 checksum..."
  if [ "$expected_sha" != "skip" ]; then
    actual_sha="$(sha256sum "$archive" 2>/dev/null | awk '{print $1}' | tr 'A-F' 'a-f')"
    exp_lower="$(printf '%s' "$expected_sha" | tr 'A-F' 'a-f')"
    if [ "$actual_sha" != "$exp_lower" ]; then
      write_job "error" "$id" 0 0 "$expected_bytes" "Checksum mismatch (got ${actual_sha:-none})"
      rm -f "$archive"
      return 1
    fi
  fi

  write_job "extracting" "$id" 95 "$expected_bytes" "$expected_bytes" "Extracting package to /data..."
  stage="$TMP_DIR/unpack_$id"
  rm -rf "$stage"
  mkdir -p "$stage"

  case "$archive" in
    *.tar.xz|*.txz)
      /data/adb/ksu/bin/busybox tar -xJf "$archive" -C "$stage"
      rc=$?
      ;;
    *.tar.gz|*.tgz)
      /data/adb/ksu/bin/busybox tar -xzf "$archive" -C "$stage"
      rc=$?
      ;;
    *.zip)
      /system/bin/unzip -qo "$archive" -d "$stage"
      rc=$?
      ;;
    *)
      rc=1
      ;;
  esac

  if [ "$rc" != "0" ] || [ ! -d "$stage/system" ]; then
    write_job "error" "$id" 0 0 "$expected_bytes" "Failed to unpack archive (missing system/ root)"
    rm -rf "$stage" "$archive"
    return 1
  fi

  # Safety check: disallow traversal or non-system top-level entries
  bad_entry="$(find "$stage" -mindepth 1 -maxdepth 1 ! -name 'system' 2>/dev/null | head -n 1)"
  if [ -n "$bad_entry" ]; then
    write_job "error" "$id" 0 0 "$expected_bytes" "Rejected unsafe archive structure"
    rm -rf "$stage" "$archive"
    return 1
  fi

  # Record leaf paths relative to $MODDIR (e.g., system/priv-app/Bixby)
  list_tmp="$INST_DIR/${id}.list.tmp"
  : > "$list_tmp"
  for sub in priv-app app etc/permissions etc/sysconfig etc/preferred-apps; do
    [ -d "$stage/system/$sub" ] || continue
    for entry in "$stage/system/$sub"/*; do
      [ -e "$entry" ] || continue
      name="${entry##*/}"
      printf 'system/%s/%s\n' "$sub" "$name" >> "$list_tmp"
    done
  done

  if [ ! -s "$list_tmp" ]; then
    write_job "error" "$id" 0 0 "$expected_bytes" "Archive contained no installable targets"
    rm -rf "$stage" "$archive" "$list_tmp"
    return 1
  fi

  chmod -R 0755 "$stage/system" 2>/dev/null
  find "$stage/system" -type f -exec chmod 0644 {} + 2>/dev/null
  chcon -R u:object_r:system_file:s0 "$stage/system" 2>/dev/null

  cp -af "$stage/system/." "$MODDIR/system/" || {
    write_job "error" "$id" 0 0 "$expected_bytes" "Failed copying files into module staging"
    rm -rf "$stage" "$archive" "$list_tmp"
    return 1
  }

  mv -f "$list_tmp" "$INST_DIR/${id}.list"
  touch "$STATE_DIR/reboot_pending"
  rm -rf "$stage" "$archive"
  write_job "done" "$id" 100 "$expected_bytes" "$expected_bytes" "Installed $id cleanly (reboot required)"
  return 0
}

worker_install() {
  id="$1"
  url="$2"
  sha="$3"
  expected_bytes="$4"
  case "$expected_bytes" in ''|*[!0-9]*) expected_bytes=0 ;; esac

  ext="tar.xz"
  case "$url" in
    *.tar.gz|*.tgz) ext="tar.gz" ;;
    *.zip) ext="zip" ;;
  esac

  part="$TMP_DIR/${id}.${ext}.part"
  final="$TMP_DIR/${id}.${ext}"
  rm -f "$part" "$final"

  write_job "downloading" "$id" 0 0 "$expected_bytes" "Connecting to download server..."

  curl -fL --connect-timeout 20 --retry 2 --retry-delay 2 -sS -o "$part" "$url" &
  curl_pid=$!

  while kill -0 "$curl_pid" 2>/dev/null; do
    cur="$(busybox stat -c %s "$part" 2>/dev/null || echo 0)"
    pct=0
    if [ "$expected_bytes" -gt 0 ]; then
      pct=$((cur * 90 / expected_bytes))
      [ "$pct" -gt 90 ] && pct=90
    fi
    write_job "downloading" "$id" "$pct" "$cur" "$expected_bytes" "Downloading package..."
    sleep 1
  done

  wait "$curl_pid"
  curl_rc=$?
  if [ "$curl_rc" != "0" ] || [ ! -s "$part" ]; then
    write_job "error" "$id" 0 0 "$expected_bytes" "Download failed (curl exit $curl_rc)"
    rm -f "$part" "$PID_FILE"
    return 1
  fi

  mv -f "$part" "$final"
  actual_sz="$(busybox stat -c %s "$final" 2>/dev/null || echo "$expected_bytes")"
  unpack_verified_archive "$id" "$final" "$sha" "$actual_sz"
  rm -f "$PID_FILE"
}

cmd_install() {
  id="$1"
  url="$2"
  sha="$3"
  expected_bytes="$4"

  validate_id "$id" || { echo "invalid pack id" >&2; return 1; }
  validate_https_url "$url" || { echo "invalid https url" >&2; return 1; }
  validate_sha "$sha" || { echo "invalid sha256" >&2; return 1; }

  if [ -f "$PID_FILE" ]; then
    jp="$(cat "$PID_FILE" 2>/dev/null)"
    if [ -n "$jp" ] && kill -0 "$jp" 2>/dev/null; then
      echo "another download/install job is already running" >&2
      return 1
    fi
  fi

  write_job "downloading" "$id" 0 0 "${expected_bytes:-0}" "Starting background download..."
  nohup sh "$0" _worker_install "$id" "$url" "$sha" "${expected_bytes:-0}" </dev/null >"$JOB_LOG" 2>&1 &
  echo "$!" > "$PID_FILE"
  echo "started"
}

cmd_install_local() {
  id="$1"
  archive="$2"
  sha="${3:-skip}"
  validate_id "$id" || { echo "invalid pack id" >&2; return 1; }
  [ -f "$archive" ] || { echo "archive not found: $archive" >&2; return 1; }
  validate_sha "$sha" || { echo "invalid sha256" >&2; return 1; }
  sz="$(busybox stat -c %s "$archive" 2>/dev/null || echo 0)"
  unpack_verified_archive "$id" "$archive" "$sha" "$sz"
}

cmd_remove() {
  id="$1"
  validate_id "$id" || { echo "invalid pack id" >&2; return 1; }
  list_file="$INST_DIR/${id}.list"
  [ -f "$list_file" ] || { echo "pack not installed" >&2; return 1; }

  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -z "$rel" ] && continue
    case "$rel" in
      system/priv-app/*|system/app/*|system/etc/permissions/*|system/etc/sysconfig/*|system/etc/preferred-apps/*)
        case "$rel" in *..*) continue ;; esac
        rm -rf "$MODDIR/$rel"
        ;;
    esac
  done < "$list_file"

  rm -f "$list_file"
  touch "$STATE_DIR/reboot_pending"
  echo "removed"
}

case "$1" in
  status) cmd_status ;;
  get_catalog) cmd_get_catalog ;;
  fetch_catalog) cmd_fetch_catalog "$2" ;;
  install) cmd_install "$2" "$3" "$4" "$5" ;;
  install_local) cmd_install_local "$2" "$3" "$4" ;;
  _worker_install) worker_install "$2" "$3" "$4" "$5" ;;
  remove) cmd_remove "$2" ;;
  clear_job) rm -f "$JOB_FILE" ;;
  set_mirror)
    val="$2"
    if [ -z "$val" ]; then
      rm -f "$MIRROR_FILE"
    else
      validate_https_url "$val" || { echo "invalid mirror url" >&2; exit 1; }
      printf '%s\n' "$val" > "$MIRROR_FILE"
    fi
    echo "ok"
    ;;
  set_mount_mode)
    case "$2" in
      auto|magic|metamodule)
        printf '%s\n' "$2" > "$MODE_FILE"
        touch "$STATE_DIR/reboot_pending"
        echo "ok"
        ;;
      *) echo "invalid mode" >&2; exit 1 ;;
    esac
    ;;
  read_log)
    tail -n 60 "$STATE_DIR/mount.log" 2>/dev/null || echo "(no mount log yet)"
    ;;
  reboot)
    (sleep 1; svc power reboot 2>/dev/null || reboot) </dev/null >/dev/null 2>&1 &
    echo "rebooting"
    ;;
  *)
    echo "usage: addon_ctl.sh {status|get_catalog|fetch_catalog|install|install_local|remove|clear_job|set_mirror|set_mount_mode|read_log|reboot}" >&2
    exit 1
    ;;
esac
