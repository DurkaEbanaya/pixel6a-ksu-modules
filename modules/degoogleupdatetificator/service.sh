#!/system/bin/sh
# NoOTA: blocks automatic system OTA download/apply on each boot.
# Reversible: uninstall.sh (or manual pm enable) restores state.
# Early-boot binder calls from our context fail with "Failed transaction"
# until system_server settles (~6-8 min on this build), so the actual work
# runs in a background daemon that retries for up to 20 minutes.
MODDIR=${0%/*}
STATE=$MODDIR/state
LOG=$MODDIR/noota.log
mkdir -p "$STATE"
log() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

COMPONENTS="
com.google.android.gms/.update.SystemUpdateService
com.google.android.gms/.update.SystemUpdatePersistentListenerService
com.google.android.gms/.update.SystemUpdateGcmTaskService
com.google.android.gms/.update.SystemUpdateActivity
com.google.android.gms/.update.OtaSuggestionActivity
com.google.android.gms/.update.UpdateFromSdCardActivity
com.google.android.gms/.update.UucNotificationReceiverService
"

# Long-running worker (executed via setsid in the background so the
# boot-completed stage never blocks on system_server readiness).
worker() {
  log worker started
  # Readiness probe: settings get must return a VALUE (null or number),
  # not an empty stdout / "cmd:" failure line.
  i=0
  while [ $i -lt 40 ]; do
    OUT=$(settings get global ota_disable_automatic_update 2>/dev/null)
    if [ "$OUT" = "null" ] || [ "$OUT" = "0" ] || [ "$OUT" = "1" ]; then
      break
    fi
    sleep 3; i=$((i+1))
  done
  log "framework probe done after $((i*3))s (OUT=$OUT)"

  # Layer 1: global policy flag (save previous value once)
  if [ ! -f "$STATE/prev_ota_setting" ]; then
    settings get global ota_disable_automatic_update >"$STATE/prev_ota_setting" 2>/dev/null
    log "saved previous ota_disable_automatic_update=$(cat "$STATE/prev_ota_setting" 2>/dev/null)"
  fi
  settings put global ota_disable_automatic_update 1 2>>"$LOG" || log "WARN: settings put failed"

  # Layer 2: disable exact GMS OTA components (package-wide NOT touched).
  # pm disable (NOT --user 0: --user variant reports "default" on this build).
  # Idempotent every boot; also re-disables if a Play update re-enables them.
  TRY=0
  while [ $TRY -lt 20 ]; do
    OK=0
    for C in $COMPONENTS; do
      R=$(pm disable "$C" 2>&1)
      case "$R" in
        *"new state: disabled"*) OK=$((OK+1));;
        *"new state: enabled"*)  : ;;   # hmm: means re-enabled by Play; retry next pass
        *) : ;;
      esac
      case "$R" in *"Failed transaction"*) break;; esac
    done
    # verify: a disabled component loses its intent-filter from dumpsys
    ENABLED=0
    ENABLED=7
  for CN in SystemUpdateService SystemUpdatePersistentListenerService \
              SystemUpdateGcmTaskService SystemUpdateActivity \
              OtaSuggestionActivity UpdateFromSdCardActivity \
              UucNotificationReceiverService; do
      pm dump com.google.android.gms 2>/dev/null | \
        sed -n "/disabledComponents:/,/enabledComponents:/p" | \
        grep -q "com.google.android.gms.update.$CN" || continue
      ENABLED=$((ENABLED-1))
    done
    if [ "$ENABLED" -eq 0 ]; then
      echo disabled >"$STATE/gms_components_disabled"
      log "all 7 GMS OTA components disabled (try $((TRY+1)))"
      break
    fi
    TRY=$((TRY+1))
    log "try $TRY: $ENABLED/7 still enabled — retry in 60s"
    sleep 60
  done
  [ "$ENABLED" -gt 0 ] && log "WARN: gave up after $TRY tries; $ENABLED/7 enabled"

  # Layer 3: best-effort stop of the apply daemon this boot
  # (init may restart it; download path is already dead via layer 2).
  stop update_engine >>"$LOG" 2>&1 || true
  log "NoOTA applied"
}

# Worker mode: re-exec of this script with the marker argument, detached
# via setsid so it survives the stage exit and never blocks boot.
if [ "$1" = "--noota-worker" ]; then
  worker
  exit 0
fi
rm -f "$STATE/worker_running"
setsid sh "$0" --noota-worker >/dev/null 2>&1 &
log "service.sh: worker launched"
