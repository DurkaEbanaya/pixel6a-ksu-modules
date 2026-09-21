#!/system/bin/sh
# DeVerizonficator v1.1: full simlock defeat on every boot stage.
#
# Verizon simlock lives in THREE places (all must go):
#  1. oobconfig shared_prefs: last_applied_simlock_config / provisioning_config
#     (FCM-delivered protobuf, carriers 310/590+311/480 gid1=BAE, 999/480 gid1=D10)
#  2. oobconfig process memory: SimLockTask re-applies Verizon rules within 1s
#     of any SIM_STATE_CHANGED sync-unfreeze — prefs-strip alone loses the race.
#     Fix: kill the process AFTER stripping prefs (fresh start finds nothing).
#  3. FCM topic subscription in prefs: subscribed/target_gcm_topics =
#     /topics/SECTION_TYPE_SIM_LOCK-50015 lets the server push the config back.
#     Fix: strip topic entries so the push has nowhere to arrive.
# Then set modem-side CarrierRestrictionRules to default:ALLOWED via
# ITelephony.setAllowedCarriers (Rac.dex, reflection, app_process).
# Validated live (bluejay CP1A.260405.005): gsm.sim.state CARD_RESTRICTED -> LOADED,
# zero SET_ALLOWED_CARRIERS re-restrictions after the sequence.

MODDIR=${0%/*}
PKG=com.google.android.apps.work.oobconfig
PREFS=/data/user/0/$PKG/shared_prefs/oobconfig_prefs.xml
LOG=$MODDIR/deverizon.log
RAC=/data/local/tmp/Rac.dex

log() { echo "$(date '+%m-%d %H:%M:%S') $1" >>"$LOG"; }

# --- 0. deploy Rac.dex (modem-side all-allowed setter) ----------------------
if [ ! -f "$RAC" ] || ! cmp -s "$MODDIR/Rac.dex" "$RAC"; then
  cp "$MODDIR/Rac.dex" "$RAC" && chmod 644 "$RAC" && chown root:root "$RAC" \
    && log "Rac.dex deployed to $RAC"
fi

rac_apply() {
  CLASSPATH=$RAC app_process /system/bin Rac 2>&1 | tr '\n' ' ' >>"$LOG"
  echo "" >>"$LOG"
}

# --- 1. strip prefs (simlock profile + FCM topic subscription) --------------
strip_prefs() {
  [ -f "$PREFS" ] || { log "prefs not found (oobconfig never provisioned?)"; return 1; }
  local dirty=0
  # one-time backup of the provisioned profile for restoration
  if grep -q "last_applied_simlock_config\|provisioning_config" "$PREFS"; then
    [ -f "$PREFS.bak" ] || { cp "$PREFS" "$PREFS.bak" && log "backup saved to $PREFS.bak"; }
    dirty=1
  fi
  # FCM topic subscription re-check every run (oobconfig may re-subscribe)
  if grep -q "SECTION_TYPE_SIM_LOCK" "$PREFS"; then
    dirty=1
  fi
  [ "$dirty" = "1" ] || return 0
  sed -i \
    -e '/<string name="last_applied_simlock_config">/,+0d' \
    -e '/<string name="provisioning_config">/,+0d' \
    -e '/subscribed_gcm_topics/,/\/set>/d' \
    -e '/target_gcm_topics/,/\/set>/d' \
    "$PREFS"
  chown $(stat -c '%u:%g' "$PREFS" 2>/dev/null || echo 10166:10166) "$PREFS"
  chmod 660 "$PREFS"
  if grep -q "last_applied_simlock_config\|SECTION_TYPE_SIM_LOCK" "$PREFS"; then
    log "WARN: keys still present after sed — manual check needed"
  else
    log "prefs stripped (simlock profile + FCM topics)"
  fi
  return 2   # prefs changed -> process restart required
}

# --- 2. kill oobconfig so in-memory config dies (and no race on restart) ----
kill_oob() {
  local pid
  for pid in $(pidof "$PKG"); do
    kill -9 "$pid" 2>/dev/null && log "killed oobconfig pid=$pid (in-memory config gone)"
  done
}

# --- 3. modem-side rules: all carriers allowed -------------------------------
apply_rules() {
  if [ -f "$RAC" ]; then
    log "applying all-carriers-allowed via Rac..."
    rac_apply
  fi
}

strip_prefs; CHANGED=$?
kill_oob
sleep 2
apply_rules
log "sim.state=$(getprop gsm.sim.state) operator=$(getprop gsm.operator.numeric)"

# --- 4. watcher: SimLockTask re-restricts within ~1s of a SIM broadcast; ----
#     catch any late re-apply (FCM redelivery, oobconfig restart with cached
#     config) and flip the modem rules back. Runs ~5 min after boot stage.
(
  i=0
  while [ $i -lt 30 ]; do
    sleep 10
    ST=$(getprop gsm.sim.state)
    case "$ST" in
      *RESTRICTED*)
        log "watcher: sim.state=$ST — re-strip + re-apply"
        strip_prefs; kill_oob; sleep 2; apply_rules
        log "watcher: sim.state=$(getprop gsm.sim.state)"
        ;;
    esac
    i=$((i+1))
  done
  log "watcher done: sim.state=$(getprop gsm.sim.state)"
) &
