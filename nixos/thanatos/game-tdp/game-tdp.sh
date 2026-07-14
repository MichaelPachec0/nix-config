#!/usr/bin/env bash
# game-tdp -- root reconciler. Boost the APU TDP while a gamemode client is
# active AND the machine is on AC; revert otherwise. The boost decision is
# authoritative on gamemode's live ClientCount (read off the user session bus),
# NOT on the /run/gamemode marker -- the marker is only a fast wake trigger, so a
# stale or hand-written marker can never force a boost. Fails safe to default on
# any error. See docs/superpowers/specs/2026-07-14-thanatos-gog-gaming-design.md.
set -euo pipefail

GAME_USER="${GAME_USER:-michael}"
POLL="${GAME_TDP_POLL:-3}"
MARKER_DIR="${GAME_TDP_MARKER_DIR:-/run/gamemode}"
AC_ONLINE="${GAME_TDP_AC:-/sys/class/power_supply/AC/online}"
FAN_MODE="${GAME_TDP_FAN:-/run/thinkfan/mode}"
OVERRIDE_FILE="${GAME_TDP_OVERRIDE:-/run/gamemode/override}"
BOOST_W="${GAME_TDP_BOOST_W:-35000}"
DEFAULT_W="${GAME_TDP_DEFAULT_W:-28000}"
# Battery: game-tdp does NOT drive ryzenadj on battery; it only knocks the limit
# down ONCE on the AC->battery transition (so a prior boost never persists), then
# leaves power management to tlp/BIOS. Keep BATTERY_W low + battery-appropriate.
BATTERY_W="${GAME_TDP_BATTERY_W:-15000}"
BOOST_TCTL="${GAME_TDP_BOOST_TCTL:-90}"
DEFAULT_TCTL="${GAME_TDP_DEFAULT_TCTL:-90}"
BATTERY_TCTL="${GAME_TDP_BATTERY_TCTL:-85}"

log() { printf 'game-tdp: %s\n' "$*"; }

# ---- pure, unit-tested helpers -------------------------------------------

# parse_clientcount: read a `busctl get-property ... ClientCount` reply on stdin
# (e.g. "u 2") and echo the integer; anything unparseable -> 0.
parse_clientcount() {
  awk '{ if ($NF ~ /^[0-9]+$/) print $NF; else print 0 }'
}

# decide <ac 0|1> <clients int> -> echoes "battery", "boost", or "default".
#   battery: not on AC  -> boost always off; game-tdp backs off ryzenadj.
#   boost:   on AC + a live gamemode client.
#   default: on AC, no client.
decide() {
  local ac="$1" clients="$2"
  case "$clients" in '' | *[!0-9]*) clients=0 ;; esac
  if [ "$ac" != "1" ]; then
    echo battery
  elif [ "$clients" -gt 0 ]; then
    echo boost
  else
    echo default
  fi
}

# ---- effectful helpers ----------------------------------------------------

ac_online() { cat "$AC_ONLINE" 2>/dev/null || echo 0; }

as_user() {
  # Run "$@" as the gaming user against their session bus. Uses setpriv, NOT
  # runuser: runuser opens a PAM session, so at the poll interval it floods the
  # journal with pam_unix(runuser:session) open/close pairs (two per poll).
  # setpriv drops privileges with plain setuid/setgid syscalls -- no PAM, no
  # session, nothing logged. D-Bus still authenticates us as the user via
  # SO_PEERCRED (the kernel-verified peer uid), so the query is unchanged.
  local uid gid
  uid="$(id -u "$GAME_USER" 2>/dev/null || echo 0)"
  gid="$(id -g "$GAME_USER" 2>/dev/null || echo 0)"
  setpriv --reuid "$uid" --regid "$gid" --init-groups \
    env XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# gamemode_clients: live ClientCount off the user session bus, WITHOUT
# D-Bus-activating gamemoded; 0 on any failure (fail-safe).
gamemode_clients() {
  local owner
  owner="$(as_user busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus NameHasOwner s com.feralinteractive.GameMode 2>/dev/null || true)"
  case "$owner" in
    *true*) : ;;
    *) echo 0; return 0 ;;
  esac
  as_user busctl --user get-property com.feralinteractive.GameMode \
    /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount \
    2>/dev/null | parse_clientcount
}

# manual_override: user override written by `game-boost` -> on|off|auto (default).
manual_override() {
  case "$(cat "$OVERRIDE_FILE" 2>/dev/null)" in
    on) echo on ;;
    off) echo off ;;
    *) echo auto ;;
  esac
}

set_fan() { # perf|auto -- mirrors amd.nix fan-mode: write /run/thinkfan/mode
  [ -w "$FAN_MODE" ] || return 0
  case "$1" in
    perf) printf 'perf\n' >"$FAN_MODE" ;;
    auto) : >"$FAN_MODE" ;;
  esac
}

ryzen() { # <watts_mW> <tctl_C>
  ryzenadj --stapm-limit "$1" --fast-limit "$1" --slow-limit "$1" \
    --apu-slow-limit "$1" --slow-time 5 --tctl-temp "$2" >/dev/null 2>&1 || true
}

apply_boost() { ryzen "$BOOST_W" "$BOOST_TCTL"; }
apply_default() { ryzen "$DEFAULT_W" "$DEFAULT_TCTL"; }
apply_battery() { ryzen "$BATTERY_W" "$BATTERY_TCTL"; }

LAST=""
reconcile() {
  local want clients
  # A manual `game-boost on|off` override wins over gamemode; `auto` (the default)
  # uses the live gamemode client count. Battery still wins in decide() either way.
  case "$(manual_override)" in
    on) clients=1 ;;
    off) clients=0 ;;
    *) clients="$(gamemode_clients)" ;;
  esac
  want="$(decide "$(ac_online)" "$clients")"
  # On AC, actively hold the target every poll (boost can drift; default reverts a
  # prior boost and holds a moderate AC cap). On battery, do NOT drive ryzenadj
  # per poll -- power management is left to tlp/BIOS; the one-time back-off on the
  # transition into battery (below) knocks any boost down so it never persists
  # off-charger.
  case "$want" in
    boost) apply_boost ;;
    default) apply_default ;;
    # battery: intentionally no per-poll ryzenadj (see the transition below)
  esac
  # The fan is shared with the user's `fan-mode` helper, so it is written only on
  # a state transition (steady state never clobbers a manual fan-mode setting).
  # The battery transition also performs the one-time ryzenadj back-off.
  if [ "$want" != "$LAST" ]; then
    case "$want" in
      boost) set_fan perf ;;
      battery)
        apply_battery
        set_fan auto
        ;;
      *) set_fan auto ;;
    esac
    log "$want"
    LAST="$want"
  fi
}

run() {
  mkdir -p "$MARKER_DIR"
  reconcile
  while true; do
    inotifywait -q -t "$POLL" -e create -e delete -e moved_to -e moved_from \
      -e attrib -e modify "$MARKER_DIR" >/dev/null 2>&1 || true
    reconcile
  done
}

if [ "${GAME_TDP_TEST:-0}" != "1" ]; then
  case "${1:-run}" in
    run) run ;;
    revert)
      # undo any boost with the AC-appropriate non-boost profile
      if [ "$(ac_online)" = "1" ]; then apply_default; else apply_battery; fi
      set_fan auto
      log "revert"
      ;;
    *)
      echo "usage: game-tdp [run|revert]" >&2
      exit 2
      ;;
  esac
fi
