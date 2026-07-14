#!/usr/bin/env bash
# Unit tests for game-tdp.sh pure helpers (decide, parse_clientcount).
# Usage: bash test_game-tdp.sh path/to/game-tdp.sh
# shellcheck disable=SC2329,SC2034 # stub fns/vars below are used indirectly by
# reconcile(), which shellcheck can't see through the dynamic `source "$1"`.
set -euo pipefail

GAME_TDP_TEST=1
export GAME_TDP_TEST
# shellcheck source=/dev/null
source "${1:?usage: test_game-tdp.sh path/to/game-tdp.sh}"

fail=0
check() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok:   %s\n' "$1"
  else
    printf 'FAIL: %s (want %q got %q)\n' "$1" "$2" "$3"
    fail=1
  fi
}

check "AC + 2 clients -> boost"        boost   "$(decide 1 2)"
check "AC + 0 clients -> default"      default "$(decide 1 0)"
check "battery + 3 clients -> battery" battery "$(decide 0 3)"
check "battery + 0 clients -> battery" battery "$(decide 0 0)"
check "battery + junk clients -> battery" battery "$(decide 0 xx)"
check "AC + junk clients -> default"   default "$(decide 1 xx)"
check "AC + empty clients -> default"  default "$(decide 1 '')"
check "parse 'u 2' -> 2"               2       "$(printf 'u 2\n' | parse_clientcount)"
check "parse 'i 0' -> 0"               0       "$(printf 'i 0\n' | parse_clientcount)"
check "parse junk -> 0"                0       "$(printf 'garbage\n' | parse_clientcount)"

# --- reconcile fan-transition behavior (fix: no steady-state fan clobber) -----
ryzen() { :; }                 # stub: no real ryzenadj in the sandbox
ac_online() { echo 1; }        # on AC
tmpfan="$(mktemp)"
FAN_MODE="$tmpfan"

gamemode_clients() { echo 0; } # -> default
LAST=""
printf 'perf\n' >"$tmpfan"     # pretend the user set fan-mode perf
reconcile                       # transition ""->default: writes auto (truncate)
check "default transition truncates fan"        ""     "$(cat "$tmpfan")"
printf 'perf\n' >"$tmpfan"     # user sets fan-mode perf again while idle
reconcile                       # steady default: must NOT touch the fan
check "steady default leaves fan-mode intact"   perf   "$(cat "$tmpfan")"
gamemode_clients() { echo 1; } # -> boost
reconcile                       # transition default->boost: writes perf
check "boost transition sets fan perf"          perf   "$(cat "$tmpfan")"
rm -f "$tmpfan"

# --- reconcile battery back-off (fix: no per-poll ryzenadj on battery) --------
# On battery ryzenadj must run ONCE on the transition and NOT every poll; the fan
# is released once. A counting ryzen stub proves the "once" behaviour.
ryzencalls=0
ryzen() { ryzencalls=$((ryzencalls + 1)); }
ac_online() { echo 0; }        # on battery
gamemode_clients() { echo 0; }
tmpfan="$(mktemp)"
FAN_MODE="$tmpfan"
LAST=boost                     # simulate unplugging while boosted (boost->battery)
printf 'perf\n' >"$tmpfan"
reconcile                       # transition boost->battery: one back-off + fan auto
check "battery transition backs off ryzen once" 1    "$ryzencalls"
check "battery transition releases fan"         ""   "$(cat "$tmpfan")"
printf 'perf\n' >"$tmpfan"     # user sets fan-mode perf while idle on battery
reconcile                       # steady battery: no ryzenadj, fan untouched
check "steady battery: no per-poll ryzenadj"    1    "$ryzencalls"
check "steady battery leaves fan-mode intact"   perf "$(cat "$tmpfan")"
rm -f "$tmpfan"

# --- manual override (game-boost on|off|auto) --------------------------------
tmpov="$(mktemp)"
OVERRIDE_FILE="$tmpov"
printf 'on\n'   >"$tmpov"; check "override file 'on'  -> on"   on   "$(manual_override)"
printf 'off\n'  >"$tmpov"; check "override file 'off' -> off"  off  "$(manual_override)"
: >"$tmpov";               check "override empty       -> auto" auto "$(manual_override)"
printf 'junk\n' >"$tmpov"; check "override junk        -> auto" auto "$(manual_override)"

# reconcile honors the override: 'on' forces boost on AC even with 0 clients;
# 'off' forces default even with a live client.
ryzen() { :; }
ac_online() { echo 1; }
gamemode_clients() { echo 0; }
tmpfan="$(mktemp)"
FAN_MODE="$tmpfan"
LAST=""
printf 'on\n' >"$tmpov"
reconcile                       # override on + AC + 0 clients -> boost
check "override on forces boost"    perf "$(cat "$tmpfan")"
gamemode_clients() { echo 1; } # a real client now present
printf 'off\n' >"$tmpov"
reconcile                       # override off -> default despite the client
check "override off forces default" ""   "$(cat "$tmpfan")"
rm -f "$tmpov" "$tmpfan"

exit "$fail"
