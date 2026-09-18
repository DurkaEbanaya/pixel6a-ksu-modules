#!/system/bin/sh
# DeVerizonficator: strips the FCM-provisioned Verizon carrier-restriction
# profile from oobconfig's shared_prefs on every boot. With the profile
# absent, SimLockTask (com.google.android.apps.work.oobconfig) applies its
# built-in fallback — CarrierRestrictionRules(all carriers allowed) — and
# the modem reports the SIM as CARDSTATE_PRESENT instead of RESTRICTED.
# Validated live on Pixel 6a (bluejay, CP1A.260405.005): radio log showed
# SET_ALLOWED_CARRIERS allowed:[] default:1 followed by CARDSTATE_PRESENT.
MODDIR=${0%/*}
PREFS=/data/user/0/com.google.android.apps.work.oobconfig/shared_prefs/oobconfig_prefs.xml
LOG=$MODDIR/deverizon.log

log() { echo "$(date '+%m-%d %H:%M:%S') $1" >>"$LOG"; }

if [ ! -f "$PREFS" ]; then
  log "prefs not found (oobconfig never provisioned?) — nothing to do"
  exit 0
fi

if grep -q "last_applied_simlock_config" "$PREFS" || grep -q "provisioning_config" "$PREFS"; then
  # Keep a one-time backup of the provisioned profile for restoration.
  if [ ! -f "$PREFS.bak" ]; then
    cp "$PREFS" "$PREFS.bak" && log "backup saved to $PREFS.bak"
  fi
  # Strip the two restriction keys with a python-style XML edit (sed on
  # the <string> elements). The rest of the prefs (GCM token etc.) stays.
  sed -i \
    -e '/<string name="last_applied_simlock_config">/,+0d' \
    -e '/<string name="provisioning_config">/,+0d' \
    "$PREFS"
  chown $(stat -c '%u:%g' "$PREFS" 2>/dev/null || echo 10166:10166) "$PREFS"
  chmod 660 "$PREFS"
  if grep -q "last_applied_simlock_config" "$PREFS"; then
    log "WARN: simlock key still present after sed — manual check needed"
  else
    log "simlock profile stripped; SimLockTask will fall back to all-carriers-allowed"
  fi
else
  log "already clean"
fi

log "sim.state=$(getprop gsm.sim.state) operator=$(getprop gsm.operator.numeric)"
