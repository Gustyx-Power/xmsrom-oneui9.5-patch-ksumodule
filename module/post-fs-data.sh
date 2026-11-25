#!/system/bin/sh
MODDIR="${0%/*}"
PATH="/data/adb/ksu/bin:/system/bin:/vendor/bin:$PATH"

STATE_DIR="/data/adb/xmsrom_addons"
LOG_FILE="$STATE_DIR/mount.log"
MODE_CONF="$STATE_DIR/mount_mode"

mkdir -p "$STATE_DIR"
: > "$LOG_FILE"
log() {
  printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo 'boot')" "$1" >> "$LOG_FILE"
}

[ -d "$MODDIR/system" ] || exit 0
if [ -z "$(find "$MODDIR/system" -mindepth 2 2>/dev/null | head -n 1)" ]; then
  log "no packs staged under $MODDIR/system; skipping mount"
  printf '%s\n' "idle" > "$STATE_DIR/active_engine"
  exit 0
fi

# Ensure consistent system_file SELinux label on staged files
chcon -R u:object_r:system_file:s0 "$MODDIR/system" 2>/dev/null

# Determine engine: nomount / external metamodule / built-in magic mount
OVERRIDE="auto"
[ -f "$MODE_CONF" ] && OVERRIDE="$(cat "$MODE_CONF" 2>/dev/null | tr -d '\r\n ')"

HAS_NOMOUNT=0
if [ -e /dev/nomount ] || [ -e /proc/nomount ] || [ -d /sys/fs/nomount ] || grep -qi 'nomount' /proc/kallsyms 2>/dev/null; then
  HAS_NOMOUNT=1
fi

HAS_METAMOD=0
if [ -d /data/adb/metamodule ] && [ ! -f /data/adb/metamodule/disable ]; then
  HAS_METAMOD=1
fi

if [ "$OVERRIDE" = "metamodule" ] || { [ "$OVERRIDE" = "auto" ] && [ "$HAS_METAMOD" = "1" ]; }; then
  if [ "$HAS_NOMOUNT" = "1" ]; then
    printf '%s\n' "nomount" > "$STATE_DIR/active_engine"
    log "NoMount metamodule active; deferring mount to VFS NoMount"
  else
    printf '%s\n' "metamodule" > "$STATE_DIR/active_engine"
    log "External KSU metamodule active; deferring mount"
  fi
  exit 0
fi

BB="/data/adb/ksu/bin/busybox"
[ -x "$BB" ] || BB="busybox"

magic_mount_dir() {
  rel="$1"
  mod_src="$MODDIR/$rel"
  target="/$rel"
  mirror="/dev/.xms_orig/$rel"

  [ -d "$mod_src" ] || return 0
  [ -d "$target" ] || { log "skip missing target $target"; return 0; }
  [ -n "$(find "$mod_src" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ] || return 0

  rm -rf "$mirror" 2>/dev/null
  mkdir -p "$mirror" || { log "failed mkdir $mirror"; return 1; }

  if ! "$BB" mount --bind "$target" "$mirror"; then
    log "ERROR: bind $target -> $mirror failed"
    rmdir "$mirror" 2>/dev/null
    return 1
  fi
  "$BB" mount --make-private "$mirror" 2>/dev/null

  if ! "$BB" mount -t tmpfs -o mode=0755,uid=0,gid=0 xmsrom_magic "$target"; then
    log "ERROR: tmpfs mount on $target failed"
    "$BB" umount "$mirror" 2>/dev/null
    rmdir "$mirror" 2>/dev/null
    return 1
  fi
  "$BB" mount --make-private "$target" 2>/dev/null
  chcon u:object_r:system_file:s0 "$target" 2>/dev/null

  # Re-bind original entries unless explicitly replaced by module
  for entry in "$mirror"/* "$mirror"/.[!.]* "$mirror"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="${entry##*/}"
    [ -e "$mod_src/$name" ] && continue

    if [ -L "$entry" ]; then
      cp -a "$entry" "$target/$name"
    elif [ -d "$entry" ]; then
      mkdir -p "$target/$name"
      chmod 0755 "$target/$name"
      chcon u:object_r:system_file:s0 "$target/$name" 2>/dev/null
      if "$BB" mount --bind "$entry" "$target/$name"; then
        "$BB" mount --make-private "$target/$name" 2>/dev/null
      else
        log "WARN: bind orig dir $name failed"
      fi
    elif [ -f "$entry" ]; then
      : > "$target/$name"
      chmod 0644 "$target/$name"
      chcon u:object_r:system_file:s0 "$target/$name" 2>/dev/null
      if "$BB" mount --bind "$entry" "$target/$name"; then
        "$BB" mount --make-private "$target/$name" 2>/dev/null
      else
        log "WARN: bind orig file $name failed"
      fi
    fi
  done

  # Bind module additions/overrides
  count=0
  for mod_entry in "$mod_src"/*; do
    [ -e "$mod_entry" ] || continue
    name="${mod_entry##*/}"
    chmod -R 0755 "$mod_entry" 2>/dev/null
    find "$mod_entry" -type f -exec chmod 0644 {} + 2>/dev/null
    chcon -R u:object_r:system_file:s0 "$mod_entry" 2>/dev/null

    if [ -d "$mod_entry" ]; then
      mkdir -p "$target/$name"
      chmod 0755 "$target/$name"
      chcon u:object_r:system_file:s0 "$target/$name" 2>/dev/null
      if "$BB" mount --bind "$mod_entry" "$target/$name"; then
        "$BB" mount --make-private "$target/$name" 2>/dev/null
        count=$((count + 1))
        log "mounted $rel/$name"
      else
        log "ERROR: bind mod dir $rel/$name failed"
      fi
    elif [ -f "$mod_entry" ]; then
      : > "$target/$name"
      chmod 0644 "$target/$name"
      chcon u:object_r:system_file:s0 "$target/$name" 2>/dev/null
      if "$BB" mount --bind "$mod_entry" "$target/$name"; then
        "$BB" mount --make-private "$target/$name" 2>/dev/null
        count=$((count + 1))
        log "mounted file $rel/$name"
      else
        log "ERROR: bind mod file $rel/$name failed"
      fi
    fi
  done

  "$BB" umount "$mirror" 2>/dev/null || umount -l "$mirror" 2>/dev/null
  rmdir "$mirror" 2>/dev/null
  log "finished $target ($count addon entries)"
}

magic_mount_dir "system/priv-app"
magic_mount_dir "system/app"
magic_mount_dir "system/etc/permissions"
magic_mount_dir "system/etc/sysconfig"

rmdir /dev/.xms_orig/system /dev/.xms_orig 2>/dev/null
printf '%s\n' "magic_mount" > "$STATE_DIR/active_engine"
log "done"
