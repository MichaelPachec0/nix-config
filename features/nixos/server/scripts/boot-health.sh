# boot-health: decides whether this boot counts as good.
#
# Runs as boot-health.service, RequiredBy boot-complete.target. If it fails,
# boot-complete.target is never reached, systemd-bless-boot never marks the
# boot entry good, and after the configured tries systemd-boot falls back to
# the previous generation. The only criterion is "can I be administered":
# a default route, sshd listening, and (when configured) the zerotier
# network reporting OK. Each check retries within its own budget because
# zerotier in particular needs a while to reach its root servers.
#
# Env: BOOT_HEALTH_SSH_PORT (22), BOOT_HEALTH_ZT_NETWORK (empty = skip),
#      BOOT_HEALTH_STEP (seconds between retries, 5).
set -euo pipefail

port=${BOOT_HEALTH_SSH_PORT:-22}
zt=${BOOT_HEALTH_ZT_NETWORK:-}
step=${BOOT_HEALTH_STEP:-5}

# wait_for NAME BUDGET_SECONDS CMD...: retry CMD until it succeeds or the
# budget is spent. With BOOT_HEALTH_STEP=0 (tests) the loop still runs
# BUDGET/1 iterations at most, so keep budgets small in tests.
wait_for() {
  local name=$1 budget=$2 spent=0
  shift 2
  until "$@"; do
    spent=$((spent + (step > 0 ? step : 1)))
    if [ "$spent" -ge "$budget" ]; then
      echo "boot-health: $name FAILED after ${budget}s"
      return 1
    fi
    sleep "$step"
  done
  echo "boot-health: $name ok after ${spent}s"
}

have_route() {
  [ -n "$(ip -4 route show default 2>/dev/null)" ] || [ -n "$(ip -6 route show default 2>/dev/null)" ]
}

sshd_listening() {
  [ -n "$(ss -H -ltn "sport = :$port" 2>/dev/null)" ]
}

zt_ok() {
  zerotier-cli listnetworks 2>/dev/null | grep -Eq "^200 listnetworks $zt .* OK "
}

wait_for "default route" 120 have_route
wait_for "sshd on :$port" 60 sshd_listening
if [ -n "$zt" ]; then
  wait_for "zerotier $zt" 300 zt_ok
else
  echo "boot-health: zerotier check skipped (no network configured)"
fi
echo "boot-health: good"
