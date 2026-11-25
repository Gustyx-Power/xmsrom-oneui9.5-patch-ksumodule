#!/system/bin/sh
STATE_DIR="/data/adb/xmsrom_selinux"
OUT_RULE="$STATE_DIR/new_avc.rule"
mkdir -p "$STATE_DIR"

echo "XMSROM SELinux Enforcing Guard"
echo "=============================="
echo "SELinux Mode  : $(getenforce 2>/dev/null)"
echo "Mode Config   : $(cat "$STATE_DIR/mode" 2>/dev/null || echo 'enforcing (default)')"
echo "Stage Config  : $(cat "$STATE_DIR/stage" 2>/dev/null || echo 'service (default)')"
echo "Guard Armed   : $([ -f "$STATE_DIR/boot_guard" ] && echo 'YES' || echo 'no')"
echo "seapp Context : $(ls -Z /system/system_ext/etc/selinux/system_ext_seapp_contexts 2>/dev/null | awk '{print $1}')"
echo ""

{ dmesg 2>/dev/null; logcat -b events,main,system,kernel -d 2>/dev/null; } | awk '
  /avc: *denied/ {
    match($0, /\{ [^}]+ \}/); perms = substr($0, RSTART+2, RLENGTH-4)
    sc=""; tc=""; cls=""; cmd=""
    for (i=1; i<=NF; i++) {
      if (substr($i,1,9)=="scontext=") { split($i,a,":"); sc=a[3] }
      else if (substr($i,1,9)=="tcontext=") { split($i,a,":"); tc=a[3] }
      else if (substr($i,1,7)=="tclass=") { cls=substr($i,8) }
      else if (substr($i,1,9)=="ioctlcmd=") { cmd=tolower(substr($i,10)) }
    }
    if (sc=="" || tc=="" || cls=="") next
    n=split(perms,p,/ +/)
    for (i=1;i<=n;i++) if (p[i]!="") print "allow " sc " " tc " " cls " " p[i]
    if (cmd!="") { if (substr(cmd,1,4)=="0xf5") cmd="0xf500-0xf5ff"; print "allowxperm " sc " " tc " " cls " ioctl " cmd }
  }
' | sort -u > "$OUT_RULE"

count="$(wc -l < "$OUT_RULE" 2>/dev/null || echo 0)"
echo "Unique AVC rules seen since boot: $count"
echo "Saved to: $OUT_RULE"
if [ "$count" -gt 0 ]; then
  echo "--- Top captured rules ---"
  head -n 25 "$OUT_RULE"
fi
echo ""
echo "Switch mode without uninstalling:"
echo "  Audit (Permissive): echo permissive > $STATE_DIR/mode && setenforce 0"
echo "  Real Enforcing    : echo enforcing > $STATE_DIR/mode && setenforce 1"
