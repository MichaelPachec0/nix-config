# Batch suspend/resume harness for the Quickshell lock protocol-error death.
#
# The fault: on resume the compositor posts a Wayland protocol error at the bar,
# libwayland destroys the client and Qt calls _exit(1), so there is no core and
# it reads as "quickshell crashed". It has fired twice in two months of daily
# suspends, so at that rate hand-driven trials catch it ~9% of the time. This
# drives the suspected precondition unattended and stops on anything abnormal.
#
# One cycle:
#   lock (via the real loginctl -> lock.target -> qs-lock-trigger path)
#   dwell locked, so the capture pool is armed and settled
#   take the external output away, and VERIFY it is gone
#   arm the RTC alarm, suspend, resume
#   give the output back, so it arrives while the lock is still up
#   check for the fault, unlock
#
# Fault signals, any of which stops the run and preserves the logs:
#   - the quickshell pid changed (the _exit(1))
#   - new "error in client communication" in the Hyprland log
#   - new "wl_display#1.error" in the WAYLAND_DEBUG ring
#   - the lock marker vanished on its own (qs-lock-watchdog ran lock-escape)
#
# Needs root only for rtcwake (arming the RTC alarm); it asks once up front and
# refreshes the sudo timestamp each cycle. There is no unprivileged substitute:
# a user-manager timer accepts WakeSystem=true but never populates
# /sys/class/rtc/rtc0/wakealarm, because the user manager has no CAP_WAKE_ALARM.

# writeShellApplication injects `set -euo pipefail`, but errexit is wrong here:
# a `grep -c` that finds nothing, a timed-out `wait_for` or a probe of a process
# that just died would abort the run instead of being classified and reported.
set +e
set -uo pipefail

CYCLES=30
SUSPEND_SEC=20
DWELL_SEC=60
DWELL_SWEEP=""
MONITOR="HDMI-A-1"
USE_MONITOR=1
MON_MODE=""
MON_POS=""
MON_SCALE=1.0
KEEP_ARRANGE=0
ARRANGE_WAS_ACTIVE=0
USE_DPMS=0
DRY_RUN=0

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MARKER="$RUNTIME/quickshell-lock.locked"
WL_LOG="${QS_WL_LOG:-$HOME/.local/state/quickshell/wl-tail.log}"
OUTDIR="$HOME/qs-suspend-repro"

usage() {
  cat <<'EOF'
hypr-suspend-repro [options]

  -n CYCLES      suspend cycles to run (default 30)
  -s SECONDS     time asleep per cycle (default 20)
  -d SECONDS     time locked before suspending (default 60)
  -D "A B C"     sweep dwell: cycle i uses the i-th value, wrapping.
                 Overrides -d. The real incidents dwelled 3 min and 61 min,
                 the negative hand-trials dwelled 2-3 s, so this is the
                 least-explored variable.
  -m NAME        output to take away each cycle (default HDMI-A-1)
  -M             do not touch any output; rely on the loss the resume
                 produces on its own
  -k             keep hypr-monitor-arrange running. It reloads the config on
                 monitorremoved, which puts the output straight back, so the
                 default is to stop it for the run and restart it after.
  -p             also DPMS the panel off before suspending
  -N             dry run: print the plan and the preflight result, do nothing
  -h             this

Stops on the first fault and writes evidence to ~/qs-suspend-repro/<stamp>/.
EOF
}

while getopts "n:s:d:D:m:MkpNh" opt; do
  case "$opt" in
    n) CYCLES="$OPTARG" ;;
    s) SUSPEND_SEC="$OPTARG" ;;
    d) DWELL_SEC="$OPTARG" ;;
    D) DWELL_SWEEP="$OPTARG" ;;
    m) MONITOR="$OPTARG" ;;
    M) USE_MONITOR=0 ;;
    k) KEEP_ARRANGE=1 ;;
    p) USE_DPMS=1 ;;
    N) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

# Most of a run happens behind a lock screen, where the originating terminal is
# not readable, so mirror to a file rather than relying on a remembered redirect.
if [ "$DRY_RUN" = 0 ]; then
  mkdir -p "$OUTDIR"
  RUNLOG="$OUTDIR/run-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$RUNLOG") 2>&1
  printf 'run log: %s\n' "$RUNLOG"
fi

say() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '%s FATAL %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Total seconds this boot spent suspended: BOOTTIME counts suspended time and
# MONOTONIC does not, so their difference is the only honest "did we really
# suspend" measurement available to a process frozen along with the machine.
suspended_total() {
  python3 -c 'import time; print(int(time.clock_gettime(time.CLOCK_BOOTTIME) - time.clock_gettime(time.CLOCK_MONOTONIC)))'
}

qs_pid() { pgrep -f 'quickshell -c task-bar' | head -1; }

hypr_log() {
  local sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
  [ -n "$sig" ] || return 1
  printf '%s\n' "$RUNTIME/hypr/$sig/hyprland.log"
}

# Not the DRM connector: writing "off" to /sys/class/drm/cardN-<output>/status
# does reach the kernel, but hypr-monitor-arrange answers monitorremoved with
# `hyprctl reload`, which re-probes and re-adds the output within a second or
# two. Fourteen cycles ran that way with the output never actually absent.
#
# hl.monitor is checked, immediate and needs no root, and goes through `hyprctl
# eval`. `hyprctl dispatch` would wrap it into hl.dispatch(<raw>), which is for
# dispatchers, not config functions.
monitor_unplug() {
  hyprctl eval "hl.monitor({output = \"$MONITOR\", disabled = true})" >/dev/null 2>&1
}

# Bringing an output back takes three things, each learned the hard way:
#  1. `disabled = false` ALONE -- a call also carrying mode/position while the
#     output is still disabled returns ok and leaves it disabled.
#  2. Possibly twice; one issued ~2 s after the disable was silently a no-op.
#  3. Geometry re-applied explicitly afterwards, because the config rule is
#     keyed on `desc:` and does not re-run on re-enable (observed: 60.00 Hz at
#     6407,0 instead of 119.98 Hz at 0,0). Hence MON_MODE/MON_POS/MON_SCALE.
monitor_replug() {
  local i=0
  while [ "$i" -lt 5 ]; do
    hyprctl eval "hl.monitor({output = \"$MONITOR\", disabled = false})" >/dev/null 2>&1
    sleep 1
    if monitor_present; then
      hyprctl eval "hl.monitor({output = \"$MONITOR\", mode = \"$MON_MODE\", position = \"$MON_POS\", scale = $MON_SCALE})" >/dev/null 2>&1
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Mode/position/scale exactly as hl.monitor wants them back.
monitor_geometry() {
  hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
for m in json.load(sys.stdin):
    if m["name"] == want:
        print("%dx%d@%.2f" % (m["width"], m["height"], m["refreshRate"]))
        print("%dx%d" % (m["x"], m["y"]))
        print(m["scale"])
        break
' "$MONITOR" 2>/dev/null
}

monitor_present() {
  hyprctl monitors -j 2>/dev/null | grep -q "\"name\": \"$MONITOR\""
}

# Not `grep -c '"name":'`: every monitor object also carries an
# activeWorkspace with its own "name", so a grep count is exactly double.
monitor_count() {
  hyprctl monitors -j 2>/dev/null |
    python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0
}

# dpms takes a TABLE. The string form hl.dsp.dpms("off") ignores both its
# action and its monitor argument and TOGGLES EVERY OUTPUT, which blanks a lit
# panel. Never use it here.
dpms() {
  hyprctl dispatch "hl.dsp.dpms({action = \"$1\", monitor = \"$2\"})" >/dev/null 2>&1
}

# No `|| echo 0` fallback: `grep -c` already prints 0 when it matches nothing
# AND exits 1, so the fallback fires on top and returns the two-line string
# "0\n0". That broke both log-based fault detectors on the first run --
# "integer expected", and a failed test is a false one, so a protocol error
# that did not also kill the client would have been missed.
count_in() {
  local n
  n="$(grep -c -- "$2" "$1" 2>/dev/null)"
  [ -n "$n" ] || n=0
  printf '%s\n' "$n"
}

# ---------------------------------------------------------------- preflight

HYPRLOG="$(hypr_log)" || die "HYPRLAND_INSTANCE_SIGNATURE unset; run this from inside the Hyprland session"
[ -r "$HYPRLOG" ] || die "cannot read $HYPRLOG"

QS_PID="$(qs_pid)"
[ -n "$QS_PID" ] || die "quickshell -c task-bar is not running"

[ -e "$MARKER" ] && die "session is already locked ($MARKER exists)"

command -v rtcwake >/dev/null || die "rtcwake not on PATH"
[ -e /sys/class/rtc/rtc0/wakealarm ] || die "no RTC wakealarm; this machine cannot self-wake"

if [ "$USE_MONITOR" = 1 ]; then
  case "$MONITOR" in
    eDP-*|LVDS-*) die "refusing to take away the internal panel ($MONITOR)" ;;
  esac
  monitor_present || die "$MONITOR is not currently an active output; plug it in or pass -M"
  {
    read -r MON_MODE
    read -r MON_POS
    read -r MON_SCALE
  } < <(monitor_geometry)
  [ -n "${MON_MODE:-}" ] || die "could not read $MONITOR geometry"
  say "$MONITOR baseline: $MON_MODE at $MON_POS scale $MON_SCALE"
  # Losing the external must not leave the session headless.
  if [ "$(monitor_count)" -lt 2 ]; then
    die "$MONITOR is the only active output; refusing to unplug it"
  fi
fi

WL_TRACING=0
if tr '\0' '\n' < "/proc/$QS_PID/environ" 2>/dev/null | grep -q '^WAYLAND_DEBUG=client$'; then
  WL_TRACING=1
fi

say "quickshell pid $QS_PID, wayland trace $([ "$WL_TRACING" = 1 ] && echo on || echo OFF)"
[ "$WL_TRACING" = 1 ] || say "WARNING: not in the debug session; a hit will not name the offending object"
say "plan: $CYCLES cycles, ${SUSPEND_SEC}s asleep, dwell ${DWELL_SWEEP:-$DWELL_SEC}s, output $([ "$USE_MONITOR" = 1 ] && echo "$MONITOR" || echo none)"

if [ "$DRY_RUN" = 1 ]; then
  say "dry run, stopping here"
  exit 0
fi

say "root is needed to arm the RTC wake alarm"
sudo -v || die "sudo authentication failed"

# hypr-monitor-arrange reloads the config on monitorremoved, which re-adds the
# output we just took away. Leaving it running is what invalidated the first
# run, so stop it unless asked not to.
if [ "$USE_MONITOR" = 1 ] && [ "$KEEP_ARRANGE" = 0 ]; then
  if systemctl --user is-active --quiet hypr-monitor-arrange.service; then
    ARRANGE_WAS_ACTIVE=1
    systemctl --user stop hypr-monitor-arrange.service
    say "stopped hypr-monitor-arrange for the run (it undoes the unplug)"
  fi
fi

BASE_HYPR_ERR="$(count_in "$HYPRLOG" 'error in client communication')"
BASE_WL_ERR="$(count_in "$WL_LOG" 'wl_display#1.error')"
say "baseline: hypr client-errors $BASE_HYPR_ERR, wire protocol errors $BASE_WL_ERR"

# ---------------------------------------------------------------- teardown

FAULT=""
cleanup() {
  local rc=$?
  say "cleaning up"
  sudo -n rtcwake -m disable -u >/dev/null 2>&1
  [ "$USE_MONITOR" = 1 ] && monitor_replug
  [ "$USE_DPMS" = 1 ] && dpms enable eDP-1
  [ "$ARRANGE_WAS_ACTIVE" = 1 ] && systemctl --user start hypr-monitor-arrange.service
  if [ -e "$MARKER" ]; then
    qs -c task-bar ipc call lock unlock >/dev/null 2>&1
    loginctl unlock-session >/dev/null 2>&1
  fi
  [ -n "$FAULT" ] && return 0
  return $rc
}
trap cleanup EXIT
trap 'say "interrupted"; exit 130' INT TERM

# ---------------------------------------------------------------- evidence

preserve() {
  local reason="$1" dir
  dir="$OUTDIR/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  printf '%s\n' "$reason" > "$dir/reason.txt"
  {
    echo "cycle=$CYCLE of $CYCLES"
    echo "dwell=$DWELL"
    echo "suspend=$SUSPEND_SEC"
    echo "monitor=$([ "$USE_MONITOR" = 1 ] && echo "$MONITOR" || echo none)"
    echo "qs_pid_start=$QS_PID"
    echo "qs_pid_now=$(qs_pid)"
  } > "$dir/context.txt"
  # The ring rewrites itself whole on every flush and on EOF, so the copy is
  # the whole surviving trace, not a tail from an offset.
  cp -f "$WL_LOG" "$dir/wl-tail.log" 2>/dev/null
  tail -n 20000 "$HYPRLOG" > "$dir/hyprland.log" 2>/dev/null
  journalctl --user -b --since "-20 min" > "$dir/journal-user.txt" 2>/dev/null
  journalctl -b --since "-20 min" > "$dir/journal-system.txt" 2>/dev/null
  say "evidence in $dir"
  grep -n 'wl_display#1.error' "$dir/wl-tail.log" 2>/dev/null | tail -5
}

check_fault() {
  local now_pid now_hypr now_wl
  now_pid="$(qs_pid)"
  now_hypr="$(count_in "$HYPRLOG" 'error in client communication')"
  now_wl="$(count_in "$WL_LOG" 'wl_display#1.error')"

  if [ -z "$now_pid" ]; then
    FAULT="quickshell is gone (pid $QS_PID died)"
  elif [ "$now_pid" != "$QS_PID" ]; then
    FAULT="quickshell restarted: pid $QS_PID -> $now_pid"
  elif [ "$now_hypr" -gt "$BASE_HYPR_ERR" ]; then
    FAULT="Hyprland logged a client communication error ($BASE_HYPR_ERR -> $now_hypr)"
  elif [ "$now_wl" -gt "$BASE_WL_ERR" ]; then
    FAULT="a Wayland protocol error reached the client ($BASE_WL_ERR -> $now_wl)"
  fi
  [ -n "$FAULT" ] && return 1
  return 0
}

# ---------------------------------------------------------------- the cycle

# Re-applying the mode makes Hyprland destroy and recreate the output, so for a
# few seconds after a replug `hyprctl monitors` legitimately does not list it
# (on the wire: global_remove at +1.4s, a new global at +5.3s). A single sample
# in that gap looks like a failure and stopped run 2 on cycle 4, so poll until
# the geometry settles rather than trusting one look.
monitor_geometry_ok() { [ "$(monitor_geometry | head -1)" = "$MON_MODE" ]; }

marker_present() { [ -e "$MARKER" ]; }
marker_absent() { [ ! -e "$MARKER" ]; }
monitor_absent() { ! monitor_present; }

# Predicates are passed as a command, not a string to eval: the string form
# needs single quotes to defer expansion, which shellcheck flags and
# writeShellApplication turns into a build failure.
wait_for() { # seconds, label, predicate command
  local limit="$1" label="$2" waited=0
  shift 2
  while ! "$@"; do
    sleep 0.2
    waited=$((waited + 1))
    if [ "$waited" -gt $((limit * 5)) ]; then
      say "timed out waiting for $label"
      return 1
    fi
  done
  return 0
}

dwell_for_cycle() {
  local i="$1"
  if [ -z "$DWELL_SWEEP" ]; then printf '%s\n' "$DWELL_SEC"; return; fi
  # shellcheck disable=SC2206
  local vals=($DWELL_SWEEP)
  printf '%s\n' "${vals[$(( (i - 1) % ${#vals[@]} ))]}"
}

CYCLE=0
DWELL="$DWELL_SEC"
STARTED_TOTAL="$(suspended_total)"

for CYCLE in $(seq 1 "$CYCLES"); do
  DWELL="$(dwell_for_cycle "$CYCLE")"
  say "--- cycle $CYCLE/$CYCLES (dwell ${DWELL}s, sleep ${SUSPEND_SEC}s) ---"

  sudo -n true 2>/dev/null || sudo -v || die "lost sudo authorization"

  # The real path: loginctl -> systemd-lock-handler -> lock.target ->
  # swaylock.service -> qs-lock-trigger. Driving the IPC directly would skip
  # whatever else lock.target pulls in, and the incidents came from this path.
  loginctl lock-session
  if ! wait_for 15 "the lock marker" marker_present; then
    FAULT="lock did not engage"; preserve "$FAULT"; break
  fi
  say "locked; dwelling ${DWELL}s so the capture pool arms and settles"
  sleep "$DWELL"

  if [ ! -e "$MARKER" ]; then
    FAULT="lock marker vanished during the dwell (qs-lock-watchdog escaped a dead lock?)"
    preserve "$FAULT"; break
  fi

  if [ "$USE_MONITOR" = 1 ]; then
    say "taking $MONITOR away"
    monitor_unplug
    # Fatal, not a warning: the first run logged "still listed" on all fourteen
    # cycles and then called every one of them clean. If the output will not
    # go, there is no experiment to run.
    if ! wait_for 10 "$MONITOR to disappear" monitor_absent; then
      FAULT="precondition not met: $MONITOR would not go away, so this cycle would prove nothing"
      preserve "$FAULT"; break
    fi
  fi

  [ "$USE_DPMS" = 1 ] && { say "DPMS off"; dpms disable eDP-1; }

  before="$(suspended_total)"
  say "arming RTC for ${SUSPEND_SEC}s and suspending"
  if ! sudo -n rtcwake -m no -u -s "$SUSPEND_SEC" >/dev/null; then
    FAULT="could not arm the RTC alarm"; preserve "$FAULT"; break
  fi
  systemctl suspend

  # The script is frozen alongside the machine, so requiring this gap to grow
  # proves a real suspend happened rather than systemctl quietly declining.
  deadline=$((SECONDS + SUSPEND_SEC + 120))
  while :; do
    sleep 1
    after="$(suspended_total)"
    [ $((after - before)) -ge $((SUSPEND_SEC / 2)) ] && break
    if [ "$SECONDS" -gt "$deadline" ]; then
      FAULT="no suspend happened within the deadline (inhibited? logind refused?)"
      preserve "$FAULT"; break 2
    fi
  done
  say "resumed after $((after - before))s asleep"

  if [ "$USE_DPMS" = 1 ]; then dpms enable eDP-1; fi

  if [ "$USE_MONITOR" = 1 ]; then
    say "giving $MONITOR back while the lock is still up"
    monitor_replug
    if ! wait_for 20 "$MONITOR to come back" monitor_present; then
      FAULT="$MONITOR did not come back; stopping rather than running blind"
      preserve "$FAULT"; break
    fi
    # A monitor stuck at the wrong mode is a changed experiment, so stop -- but
    # only after the recreate flap above has had time to settle.
    if ! wait_for 25 "$MONITOR geometry to settle at $MON_MODE" monitor_geometry_ok; then
      FAULT="$MONITOR settled at '$(monitor_geometry | head -1)', expected $MON_MODE"
      preserve "$FAULT"; break
    fi
  fi

  # Give the compositor and the bar a moment to react to the arriving output
  # before judging. The death, when it happens, is immediate.
  sleep 5

  if ! check_fault; then
    say "FAULT: $FAULT"
    preserve "$FAULT"
    break
  fi

  qs -c task-bar ipc call lock unlock >/dev/null 2>&1
  loginctl unlock-session >/dev/null 2>&1
  wait_for 10 "the lock to clear" marker_absent || say "note: marker still present"
  sleep 2
  say "cycle $CYCLE clean"
done

# ---------------------------------------------------------------- summary

TOTAL_SLEPT=$(( $(suspended_total) - STARTED_TOTAL ))
say "=========================================="
if [ -n "$FAULT" ]; then
  say "REPRODUCED on cycle $CYCLE after ${TOTAL_SLEPT}s of total sleep"
  say "$FAULT"
  say "the session is left as-is for inspection; qs-lock-watchdog will have"
  say "released a stranded lock, or SUPER+CONTROL+ALT+l runs lock-escape"
  exit 1
fi
say "clean: $CYCLES cycles, ${TOTAL_SLEPT}s total sleep, no fault"
say "pool arms observed: $(count_in "$WL_LOG" 'pool built')"
# The ring holds a fixed LINE count (200k), which at the bar's traffic rate is
# about half an hour. Enough to preserve a fault, since a fault stops the run
# immediately, but a clean run's trace is gone within the hour.
say "note: the wire ring only spans ~30 min; this run's trace expires shortly"
say "if this stays clean at 40+ cycles the precondition is not sufficient on"
say "its own, and the next variable to vary is dwell (-D) or the DPMS flag (-p)"
