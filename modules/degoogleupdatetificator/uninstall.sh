#!/system/bin/sh
# Restore all state changed by NoOTA (run as root; executed by manager if
# supported, otherwise manual: sh /data/adb/modules/noota/uninstall.sh)
MODDIR=${0%/*}
LOG=$MODDIR/noota.log
log() { echo "$(date '+%m-%d %H:%M:%S') $1" >>"$LOG"; }
PREV=$(cat "$MODDIR/state/prev_ota_setting" 2>/dev/null)
if [ -n "$PREV" ] && [ "$PREV" != "null" ]; then
  settings put global ota_disable_automatic_update "$PREV"
  log "restored ota_disable_automatic_update=$PREV"
else
  settings delete global ota_disable_automatic_update
  log "cleared ota_disable_automatic_update"
fi
if [ -f "$MODDIR/state/gms_components_disabled" ]; then
  for C in \
    com.google.android.gms/.update.SystemUpdateService \
    com.google.android.gms/.update.SystemUpdatePersistentListenerService \
    com.google.android.gms/.update.SystemUpdateGcmTaskService \
    com.google.android.gms/.update.SystemUpdateActivity \
    com.google.android.gms/.update.OtaSuggestionActivity \
    com.google.android.gms/.update.UpdateFromSdCardActivity \
  ; do
    pm enable "$C" >>"$LOG" 2>&1
  done
  log "re-enabled GMS update components"
fi
