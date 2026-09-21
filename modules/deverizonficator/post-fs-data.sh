#!/system/bin/sh
# DeVerizonficator post-fs-data stage: deploy Rac.dex early (before user unlock)
# and make sure the module's own scripts are present and executable. This runs
# before /data/user/0 is decrypted, so prefs work is left to service.sh.
MODDIR=${0%/*}
LOG=$MODDIR/deverizon.log
RAC=/data/local/tmp/Rac.dex

log() { echo "$(date '+%m-%d %H:%M:%S') [pfd] $1" >>"$LOG"; }

mkdir -p /data/adb/deverizonficator

# Persist a known-good runtime env for app_process: KernelSU stages have no
# BOOTCLASSPATH, and app_process then silently no-ops (see service.sh).
ENVFILE=/data/adb/deverizonficator/env.sh
if [ ! -f "$ENVFILE" ] && [ -f "$MODDIR/env.sh" ]; then
  cp "$MODDIR/env.sh" "$ENVFILE" && chmod 600 "$ENVFILE"
  log "env.sh deployed"
fi

if [ -f "$MODDIR/Rac.dex" ]; then
  if [ ! -f "$RAC" ] || ! cmp -s "$MODDIR/Rac.dex" "$RAC"; then
    cp "$MODDIR/Rac.dex" "$RAC" && chmod 644 "$RAC" && chown root:root "$RAC"
    restorecon "$RAC" 2>/dev/null
    log "Rac.dex deployed"
  fi
else
  log "WARN Rac.dex missing from module dir"
fi

chmod 755 "$MODDIR/service.sh" "$MODDIR/post-fs-data.sh" 2>/dev/null
log "post-fs-data done"
