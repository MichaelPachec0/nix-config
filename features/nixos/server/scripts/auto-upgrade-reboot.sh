# auto-upgrade-reboot: activate a staged generation by rebooting, inside
# the window only.
#
# Runs as OnSuccess= of nixos-upgrade.service. The upgrade only ever runs
# `nixos-rebuild boot`, so a new generation sits in the system profile and
# on the ESP until a reboot. Upstream system.autoUpgrade.allowReboot only
# reboots when the kernel changed and would leave a userspace-only
# generation staged forever; this compares the whole generation instead.
# Outside the window it exits 0 and says "pending": the next nightly run
# stages nothing new and lands here again.
#
# Env: BOOTED_SYSTEM (/run/booted-system), SYSTEM_PROFILE
#      (/nix/var/nix/profiles/system), WINDOW_LOWER/WINDOW_UPPER (HH:MM),
#      AUTO_UPGRADE_NOW (HH:MM override for tests), SHUTDOWN (shutdown).
set -euo pipefail

booted=$(readlink -f "${BOOTED_SYSTEM:-/run/booted-system}")
staged=$(readlink -f "${SYSTEM_PROFILE:-/nix/var/nix/profiles/system}")
lower=${WINDOW_LOWER:?}
upper=${WINDOW_UPPER:?}
now=${AUTO_UPGRADE_NOW:-$(date +%H:%M)}

if [ "$booted" = "$staged" ]; then
  echo "auto-upgrade-reboot: nothing staged (booted = profile)"
  exit 0
fi

# HH:MM strings compare correctly as strings.
in_window=false
if [[ "$lower" < "$upper" ]]; then
  [[ "$now" > "$lower" && "$now" < "$upper" ]] && in_window=true
else
  # window crosses midnight, e.g. 23:00-05:00
  [[ "$now" > "$lower" || "$now" < "$upper" ]] && in_window=true
fi

if [ "$in_window" = true ]; then
  echo "auto-upgrade-reboot: staged $staged differs from booted $booted; rebooting in 1 minute"
  "${SHUTDOWN:-shutdown}" -r +1 "auto-upgrade: rebooting into the staged generation"
else
  echo "auto-upgrade-reboot: staged generation pending, $now is outside $lower-$upper"
fi
