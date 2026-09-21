# boot-health-timeout: burn a boot try when the new generation is up but
# never became healthy.
#
# Fired once by boot-health-timeout.timer (OnBootSec). systemd-bless-boot
# reports "indeterminate" while the booted entry still carries a counter,
# "good"/"bad" once decided, "clean" when the entry was never counted. Only
# an indeterminate entry whose boot-complete.target is still inactive gets
# rebooted; a known-good generation with a transient network problem is
# left alone.
#
# Env: BLESS_BOOT (path to systemd-bless-boot).
set -euo pipefail

status=$("${BLESS_BOOT:-systemd-bless-boot}" status)
if [ "$status" = indeterminate ] && ! systemctl is-active --quiet boot-complete.target; then
  echo "boot-health-timeout: entry still $status and boot-complete.target inactive; rebooting to burn a try"
  systemctl reboot
else
  echo "boot-health-timeout: status=$status, nothing to do"
fi
