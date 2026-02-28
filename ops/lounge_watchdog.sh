#!/usr/bin/env bash
set -u
set -o pipefail

# ---- Auth (no hardcoded secrets) ----
# Prefer env TOKEN. Optional TOKEN_FILE fallback.
TOKEN="${TOKEN:-}"
TOKEN_FILE="${TOKEN_FILE:-/home/pi/.config/lounge_watchdog/token}"
if [[ -z "$TOKEN" && -f "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
fi

API_BASE="${API_BASE:-http://127.0.0.1:8123/api}"

A_IMG="/opt/homeassistant/www/ProjectorA4k.jpg"
B_IMG="/opt/homeassistant/www/Projector B 4k.jpg"
[ -f "$A_IMG" ] || A_IMG="/opt/homeassistant/www/Projector A 4k.jpg"
[ -f "$B_IMG" ] || B_IMG="/opt/homeassistant/www/Projector B 4k.jpg"
[ -f "$B_IMG" ] || B_IMG="$A_IMG"

A_IP="${A_IP:-192.168.0.11}"
B_IP="${B_IP:-192.168.0.12}"

A_ENTITY="${A_ENTITY:-media_player.a_wall}"
B_ENTITY="${B_ENTITY:-media_player.ha90}"

LOG_FILE="${LOG_FILE:-/home/pi/lounge_watchdog.log}"

# Tuning
POLL_S="${POLL_S:-5}"
IDLE_POLLS_BEFORE_APPLY="${IDLE_POLLS_BEFORE_APPLY:-2}"
MIN_SECONDS_BETWEEN_APPLY="${MIN_SECONDS_BETWEEN_APPLY:-20}"
GUARD_CHECK_INTERVAL="${GUARD_CHECK_INTERVAL:-30}"

# Focus match: vary by device. Default keeps original behavior.
FOCUS_REGEX="${FOCUS_REGEX:-gallery3d}"

# Quiet hours (Eastern): stop actions at 01:00 and resume at 09:00.
QUIET_START_H="${QUIET_START_H:-1}"
QUIET_END_H="${QUIET_END_H:-9}"
TZ_EASTERN="${TZ_EASTERN:-America/New_York}"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "fatal missing_cmd=$1"; echo "Missing required command: $1" >&2; exit 1; }
}

in_quiet_hours() {
  local h
  h="$(TZ="$TZ_EASTERN" date +%H)" || return 1
  h="${h#0}"
  [[ -z "$h" ]] && h=0
  (( h >= QUIET_START_H && h < QUIET_END_H ))
}

ha_state_json() {
  local entity="$1"
  local url="${API_BASE}/states/${entity}"

  if [[ -z "$TOKEN" ]]; then
    log "fatal missing_token token_file='${TOKEN_FILE}'"
    echo "TOKEN is not set (export TOKEN or create TOKEN_FILE)" >&2
    exit 1
  fi

  local tmp http
  tmp="$(mktemp)"
  http="$(curl -sS -o "$tmp" -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "$url" || true)"

  if [[ "$http" != "200" ]]; then
    local snippet
    snippet="$(head -c 200 "$tmp" | tr '\n' ' ' | tr '\r' ' ')"
    log "ha_state_error entity=${entity} http=${http} body_snip='${snippet}'"
    rm -f "$tmp"
    return 1
  fi

  cat "$tmp"
  rm -f "$tmp"
  return 0
}

get_state() {
  local entity="$1"
  ha_state_json "$entity" | python3 -c 'import sys,json
try:
 d=json.load(sys.stdin); print(d.get("state","unknown"))
except Exception:
 print("unknown")' 2>/dev/null || echo "unknown"
}

focus_has_viewer() {
  local ip="$1"
  adb -s "${ip}:5555" shell dumpsys window 2>/dev/null \
    | grep -E "mCurrentFocus|mFocusedApp" \
    | tail -n 5 \
    | grep -Eqi "$FOCUS_REGEX"
}

adb_ready() {
  local ip="$1"
  adb connect "${ip}:5555" >/dev/null 2>&1 || true
  adb -s "${ip}:5555" get-state >/dev/null 2>&1
}

apply_image() {
  local ip="$1" img="$2" outname="$3"

  if [[ ! -f "$img" ]]; then
    log "apply_fail ip=${ip} reason=missing_file img='${img}'"
    return 1
  fi

  if ! adb_ready "$ip"; then
    log "apply_fail ip=${ip} reason=adb_not_ready"
    return 1
  fi

  adb -s "${ip}:5555" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb -s "${ip}:5555" shell cmd dream stop-dreaming >/dev/null 2>&1 || true

  if ! adb -s "${ip}:5555" push "$img" "/sdcard/Download/${outname}" >/dev/null 2>&1; then
    log "apply_fail ip=${ip} reason=adb_push_failed img='${img}'"
    return 1
  fi

  if ! adb -s "${ip}:5555" shell am start \
      -a android.intent.action.VIEW \
      -d "file:///sdcard/Download/${outname}" \
      -t image/jpeg >/dev/null 2>&1; then
    log "apply_fail ip=${ip} reason=am_start_failed outname='${outname}'"
    return 1
  fi

  sleep 1
  if focus_has_viewer "$ip"; then
    return 0
  fi

  log "apply_warn ip=${ip} reason=focus_not_matched regex='${FOCUS_REGEX}'"
  return 0
}

need_cmd curl
need_cmd adb
need_cmd python3

log "start api='${API_BASE}' a_entity='${A_ENTITY}' b_entity='${B_ENTITY}' a_ip=${A_IP} b_ip=${B_IP} focus_regex='${FOCUS_REGEX}' quiet_hours=${QUIET_START_H}-${QUIET_END_H} tz='${TZ_EASTERN}'"

idle_polls=0
last_apply_ts=0
last_guard_ts=0
last_quiet_hr=""

while true; do
  now="$(date +%s)"

  if in_quiet_hours; then
    cur_hr="$(TZ="$TZ_EASTERN" date +%Y-%m-%dT%H)"
    if [[ "$last_quiet_hr" != "$cur_hr" ]]; then
      log "quiet_hours active tz='${TZ_EASTERN}'"
      last_quiet_hr="$cur_hr"
    fi

    idle_polls=0
    sleep "$POLL_S"
    continue
  else
    last_quiet_hr=""
  fi

  a_state="$(get_state "$A_ENTITY")"
  b_state="$(get_state "$B_ENTITY")"

  if [[ "$a_state" != "playing" && "$b_state" != "playing" ]]; then
    idle_polls=$((idle_polls + 1))
  else
    idle_polls=0
  fi

  if [[ $idle_polls -ge $IDLE_POLLS_BEFORE_APPLY && $((now - last_apply_ts)) -ge $MIN_SECONDS_BETWEEN_APPLY ]]; then
    ok_a=0; ok_b=0
    apply_image "$A_IP" "$A_IMG" "ProjectorA4k.jpg" && ok_a=1
    apply_image "$B_IP" "$B_IMG" "ProjectorB4k.jpg" && ok_b=1
    log "wallpaper_applied ok_a=${ok_a} ok_b=${ok_b} a_state=${a_state} b_state=${b_state}"
    last_apply_ts="$now"
    idle_polls=0
  fi

  if [[ "$a_state" != "playing" && "$b_state" != "playing" && $((now - last_guard_ts)) -ge $GUARD_CHECK_INTERVAL ]]; then
    if ! focus_has_viewer "$A_IP"; then
      apply_image "$A_IP" "$A_IMG" "ProjectorA4k.jpg" >/dev/null 2>&1 || true
    fi
    if ! focus_has_viewer "$B_IP"; then
      apply_image "$B_IP" "$B_IMG" "ProjectorB4k.jpg" >/dev/null 2>&1 || true
    fi
    log "launcher_guard_checked"
    last_guard_ts="$now"
  fi

  sleep "$POLL_S"
done
