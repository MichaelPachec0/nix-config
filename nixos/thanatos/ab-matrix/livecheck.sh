#!/usr/bin/env bash
# Read-only check that the harness's probes work against the real system.
# Everything here is a read; no tunable is touched.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
AB_LATENCY_SOURCED=1 . "$here/ab-latency.sh"

echo "zenpower temp:        '$(hwmon_temp zenpower)'  (empty = sensor not found)"
echo "user.slice cpu some:  '$(psi_total "$USER_SLICE" cpu some)'"
echo "user.slice io some:   '$(psi_total "$USER_SLICE" io some)'"
echo "user.slice io full:   '$(psi_total "$USER_SLICE" io full)'"
echo "user.slice mem some:  '$(psi_total "$USER_SLICE" memory some)'"
echo "cpu.weight user/sys:  $(cat "$USER_SLICE/cpu.weight")/$(cat "$SYS_SLICE/cpu.weight")"
echo "nvme schedulers:      $(cat "$SCHED_PATH")"
echo "probe read file:      $READFILE"
