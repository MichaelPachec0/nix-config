#!/usr/bin/env bash
# Average discharge in watts, from the energy_now delta across a fixed window.
#
# upower's energy-rate (and power_now) is a smoothed instantaneous reading that
# wanders by 1-2 W on its own, which cannot resolve the 0.5-1 W changes a single
# power tuning produces. Integrating energy_now over a window removes that noise
# because it measures charge actually consumed rather than an instantaneous
# estimate.
#
# The full measurement protocol (120s pre-idle settle, then `median 3` of 600s
# windows) runs for roughly 1920s of no input, which is longer than this
# machine's idle-suspend tier. Arm the stay-awake idle inhibitor (the
# Quickshell "stay awake" popup, or equivalent) for the whole session before
# starting a measurement run, or a suspend firing mid-window will make `once`
# exit 3 (see below) and discard the sample.
set -euo pipefail

BATT_DIR="${BATT_DIR:-/sys/class/power_supply/BAT0}"
AC_DIR="${AC_DIR:-/sys/class/power_supply/AC}"

# watts_from_delta START_UWH END_UWH WINDOW_SECONDS
# energy_now is microwatt-hours, so:
#   W = (delta_uWh / 1e6) / (window_s / 3600) = delta_uWh * 3600 / (window_s * 1e6)
# Prints two decimal places. A negative result means the pack gained energy,
# i.e. the sample was taken while charging and is not valid.
watts_from_delta() {
  local start="$1" end="$2" window="$3"
  awk -v s="$start" -v e="$end" -v w="$window" \
    'BEGIN { printf "%.2f\n", (s - e) * 3600 / (w * 1000000) }'
}

# median_of VALUE...
median_of() {
  printf '%s\n' "$@" | sort -g | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'
}

require_discharging() {
  if [ -r "$AC_DIR/online" ] && [ "$(cat "$AC_DIR/online")" != "0" ]; then
    echo "batt-watts: AC is online; unplug before measuring" >&2
    exit 2
  fi
}

once() {
  local window="${1:-600}"
  local poll_interval=5
  if [ "$window" -le 0 ]; then
    echo "batt-watts: WINDOW_SECONDS must be > 0 (got '$window')" >&2
    exit 64
  fi
  require_discharging
  local start end elapsed remaining slept=0
  start="$(cat "$BATT_DIR/energy_now")"
  SECONDS=0
  # Poll AC every ~5s instead of one long sleep, so a plug-in that is
  # unplugged again before the window ends still gets caught. SECONDS is a
  # bash builtin (monotonic-ish wall clock since it was last assigned), so
  # elapsed reflects the actual time slept rather than the requested window.
  while [ "$SECONDS" -lt "$window" ]; do
    remaining=$((window - SECONDS))
    if [ "$remaining" -lt "$poll_interval" ]; then
      sleep "$remaining"
      slept=$((slept + remaining))
    else
      sleep "$poll_interval"
      slept=$((slept + poll_interval))
    fi
    require_discharging
  done
  elapsed=$SECONDS
  # sleep uses CLOCK_MONOTONIC, which does not advance across suspend; SECONDS
  # is wall clock and does. If the machine suspended mid-window, the loop above
  # still exits (SECONDS caught up once resumed) but elapsed is inflated by the
  # whole suspended interval while energy_now barely moved -- watts_from_delta
  # would then divide a small delta by a large window and silently print an
  # artificially LOW wattage that passes require_discharging and looks
  # plausible. Detect it by comparing elapsed against the sleep time actually
  # accumulated: more than 10s of drift means a suspend happened, not just
  # scheduling jitter.
  if [ "$((elapsed - slept))" -gt 10 ]; then
    echo "batt-watts: wall time (${elapsed}s) outran slept time (${slept}s) by more than 10s; the system suspended mid-window, discarding this sample" >&2
    exit 3
  fi
  end="$(cat "$BATT_DIR/energy_now")"
  require_discharging
  watts_from_delta "$start" "$end" "$elapsed"
}

median() {
  local n="${1:?usage: batt-watts median N [WINDOW_SECONDS]}"
  local window="${2:-600}"
  local samples=() i w
  for ((i = 1; i <= n; i++)); do
    w="$(once "$window")"
    echo "sample $i/$n: $w W" >&2
    samples+=("$w")
  done
  median_of "${samples[@]}"
}

# Sourced by the test suite: define the functions, run nothing.
if [ -n "${BATT_WATTS_LIB_ONLY:-}" ]; then
  # shellcheck disable=SC2317  # reached only when the test suite sources this
  return 0 2>/dev/null || exit 0
fi

case "${1:-}" in
  once) shift; once "$@" ;;
  median) shift; median "$@" ;;
  *)
    echo "usage: batt-watts once [WINDOW_SECONDS]" >&2
    echo "       batt-watts median N [WINDOW_SECONDS]" >&2
    exit 64
    ;;
esac
