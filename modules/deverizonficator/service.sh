#!/system/bin/sh
# DeVerizonficator v1.2 — full simlock defeat, hardened.
#
# Verizon simlock lives in three places (all must go):
#  1. oobconfig shared_prefs: last_applied_simlock_config / provisioning_config
#     (FCM-delivered protobuf) + the FCM topic subscription that re-delivers it.
#  2. oobconfig process memory: SimLockTask re-applies Verizon rules within ~1s
#     of any SIM_STATE_CHANGED sync-unfreeze (am freeze does not hold).
#  3. Modem-side CarrierRestrictionRules: set to all-carriers-allowed via
#     ITelephony.setAllowedCarriers (Rac.dex, app_process reflection).
#
# v1.2 hardening (over v1.1):
#  - toybox-portable sed: no GNU ",+0d"; removes only exact entry lines, never
#    a whole <set>; edits a temp file and renames atomically.
#  - process is stopped BEFORE editing prefs (no write race), and the kill is
#    verified with a bounded pidof poll.
#  - owner/mode/SELinux context preserved on the edited prefs; backup lives in
#    a root-only module dir.
#  - Rac.dex v2 returns structured exit codes and verifies the readback.
#  - watcher is a singleton (mkdir lock) and runs 60 min, re-arming on either
#    RESTRICTED state or re-provisioned prefs, so late KSU stages are covered.

MODDIR=${0%/*}
PKG=com.google.android.apps.work.oobconfig
APPDIR=/data/user/0/$PKG
PREFS=$APPDIR/shared_prefs/oobconfig_prefs.xml
LOG=$MODDIR/deverizon.log
BACKUP=/data/adb/deverizonficator/oobconfig_prefs.xml.bak
RAC=/data/local/tmp/Rac.dex
ENVFILE=/data/adb/deverizonficator/env.sh
LOCK=/data/local/tmp/.deverizon.watch.lock
WATCH_ITERS=1080
WATCH_SLEEP=20

log() {
  echo "$(date '+%m-%d %H:%M:%S') $1" >>"$LOG"
  if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
    mv -f "$LOG" "$LOG.1" 2>/dev/null
  fi
}

# --- 0a. runtime env for app_process ---------------------------------------
# KernelSU runs module scripts with a stripped environment: BOOTCLASSPATH /
# ANDROID_* are absent, and app_process then exits 0 WITHOUT running main()
# (silent no-op — the bug that made the module do nothing after a reboot).
# Persist a known-good env and restore it whenever the stage env is bare.
prepare_env() {
  if [ -n "$BOOTCLASSPATH" ]; then
    mkdir -p /data/adb/deverizonficator
    : >"$ENVFILE"
    for v in ANDROID_DATA DEX2OATBOOTCLASSPATH ANDROID_TZDATA_ROOT ANDROID_ROOT \
             BOOTCLASSPATH ANDROID_ART_ROOT TMPDIR PATH ANDROID_I18N_ROOT; do
      eval "val=\$$v"
      [ -n "$val" ] && echo "export $v=$val" >>"$ENVFILE"
    done
    chmod 600 "$ENVFILE"
    return 0
  fi
  if [ -f "$ENVFILE" ]; then
    . "$ENVFILE"
    return 0
  fi
  if [ -f "$MODDIR/env.sh" ]; then
    mkdir -p /data/adb/deverizonficator
    cp "$MODDIR/env.sh" "$ENVFILE" && chmod 600 "$ENVFILE"
    . "$ENVFILE"
    return 0
  fi
  log "WARN no BOOTCLASSPATH and no env.sh — app_process will no-op"
  return 1
}

# --- 0. deploy Rac.dex ------------------------------------------------------
deploy_rac() {
  [ -f "$MODDIR/Rac.dex" ] || { log "WARN Rac.dex missing from module dir"; return 1; }
  if [ ! -f "$RAC" ] || ! cmp -s "$MODDIR/Rac.dex" "$RAC"; then
    cp "$MODDIR/Rac.dex" "$RAC" && chmod 644 "$RAC" && chown root:root "$RAC" \
      && restorecon "$RAC" 2>/dev/null
    log "Rac.dex deployed"
  fi
  return 0
}

# --- 1. stop oobconfig, verified -------------------------------------------
stop_oob() {
  local pid pids i
  pids=$(pidof "$PKG" 2>/dev/null)
  [ -z "$pids" ] && return 0
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null && log "killed oobconfig pid=$pid"
  done
  i=0
  while [ $i -lt 20 ]; do
    [ -z "$(pidof "$PKG" 2>/dev/null)" ] && return 0
    sleep 0.25
    i=$((i+1))
  done
  log "WARN oobconfig still running after kill poll"
  return 1
}

# --- 2. strip prefs (temp file + atomic rename), preserving metadata --------
strip_prefs() {
  [ -f "$PREFS" ] || { log "prefs not found"; return 1; }

  local before after owner mode changed
  before=$(wc -c <"$PREFS" 2>/dev/null || echo 0)
  owner=$(stat -c '%u:%g' "$PREFS" 2>/dev/null || stat -c '%u:%g' "$APPDIR" 2>/dev/null || echo "")
  mode=$(stat -c '%a' "$PREFS" 2>/dev/null || echo "660")

  local tmp="$PREFS.dvtmp"
  cp "$PREFS" "$tmp" || { log "ERR cannot create temp"; return 1; }

  # backup once, root-only, verified before the first modification
  if grep -q "last_applied_simlock_config\|provisioning_config" "$PREFS"; then
    if [ ! -f "$BACKUP" ]; then
      mkdir -p /data/adb/deverizonficator
      cp "$PREFS" "$BACKUP" && chmod 600 "$BACKUP" && log "backup saved to $BACKUP"
    fi
  fi

  # exact-entry deletion only (no whole-set deletion, no GNU address forms)
  sed -i \
    -e '/<string name="last_applied_simlock_config">/d' \
    -e '/<string name="provisioning_config">/d' \
    -e '/SECTION_TYPE_SIM_LOCK/d' \
    "$tmp" || { log "ERR sed failed"; rm -f "$tmp"; return 1; }

  # sanity: still a valid prefs file
  if ! grep -q "</map>" "$tmp"; then
    log "ERR edited prefs look corrupt — keeping original"
    rm -f "$tmp"
    return 1
  fi

  after=$(wc -c <"$tmp" 2>/dev/null || echo 0)
  changed=0
  [ "$before" != "$after" ] && changed=1

  [ -n "$owner" ] && chown "$owner" "$tmp" 2>/dev/null
  chmod "$mode" "$tmp" 2>/dev/null
  mv -f "$tmp" "$PREFS" || { log "ERR rename failed"; return 1; }
  restorecon "$PREFS" 2>/dev/null

  if grep -q "last_applied_simlock_config\|SECTION_TYPE_SIM_LOCK" "$PREFS"; then
    log "WARN keys still present after strip"
    return 1
  fi
  [ "$changed" = "1" ] && log "prefs stripped (simlock profile + FCM topics)" || log "prefs already clean"
  return 0
}

prefs_dirty() {
  [ -f "$PREFS" ] || return 1
  grep -q "last_applied_simlock_config\|SECTION_TYPE_SIM_LOCK" "$PREFS"
}

# --- 3. modem rules: all carriers allowed ----------------------------------
apply_rac() {
  [ -f "$RAC" ] || { log "ERR Rac.dex missing"; return 1; }
  local out rc
  out=$(CLASSPATH=$RAC app_process /system/bin Rac 2>&1)
  rc=$?
  case "$out" in
    *OK*)
      log "Rac ok rc=$rc out=$(echo "$out" | tr '\n' ' ')"
      return 0
      ;;
  esac
  log "Rac FAILED rc=$rc out=$(echo "$out" | tr '\n' ' ')"
  return 1
}

enforce() {
  prepare_env
  deploy_rac
  stop_oob
  strip_prefs
  stop_oob          # respawn during edit is possible; kill again before rules
  apply_rac || { log "Rac retry after env re-prepare"; prepare_env; apply_rac; }
  log "enforce done: sim.state=$(getprop gsm.sim.state) operator=$(getprop gsm.operator.numeric)"
}

# --- 4. singleton watcher (detached via setsid, ~6h coverage) ---------------
start_watcher() {
  if [ -d "$LOCK" ]; then
    OLD=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
      log "watcher already running (pid=$OLD)"
      return 0
    fi
    rm -rf "$LOCK"
  fi
  if ! mkdir "$LOCK" 2>/dev/null; then
    log "watcher lock busy"
    return 0
  fi
  setsid sh -c '
    LOCK="'"$LOCK"'"; LOG="'"$LOG"'"; ITERS='"$WATCH_ITERS"'; SL='"$WATCH_SLEEP"'
    echo $$ >"$LOCK/pid"
    log() { echo "$(date "+%m-%d %H:%M:%S") $1" >>"$LOG"; }
    i=0
    while [ $i -lt $ITERS ]; do
      sleep $SL
      ST=$(getprop gsm.sim.state)
      case "$ST" in
        *RESTRICTED*) log "watcher: sim.state=$ST — re-enforce"; sh "'"$MODDIR"'/service.sh" once ;;
        *) grep -q "last_applied_simlock_config\|SECTION_TYPE_SIM_LOCK" \
             /data/user/0/'"$PKG"'/shared_prefs/oobconfig_prefs.xml 2>/dev/null \
             && { log "watcher: prefs re-provisioned — re-enforce"; sh "'"$MODDIR"'/service.sh" once; } ;;
      esac
      i=$((i+1))
    done
    log "watcher done: sim.state=$(getprop gsm.sim.state)"
    rm -rf "$LOCK"
  ' </dev/null >/dev/null 2>&1 &
  sleep 1
  WP=$(cat "$LOCK/pid" 2>/dev/null)
  log "watcher started (pid=$WP, ${WATCH_ITERS}x${WATCH_SLEEP}s)"
}

if [ "$1" = "once" ]; then
  enforce
  exit 0
fi

enforce
start_watcher
