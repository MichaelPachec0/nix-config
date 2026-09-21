#!/usr/bin/env bash
# Runs scripts/boot-health-timeout.sh against stubbed systemctl and
# systemd-bless-boot. The script must reboot only when the booted entry is
# still counted (status indeterminate) AND boot-complete.target is inactive.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/boot-health-timeout.sh"
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$stubs/$1"; chmod +x "$stubs/$1"; }
export PATH="$stubs:$PATH" BLESS_BOOT="$stubs/bless"

# systemctl stub: "is-active --quiet boot-complete.target" exits per TARGET_ACTIVE;
# "reboot" records itself.
mkstub systemctl 'case "$1" in is-active) [ "${TARGET_ACTIVE:-0}" = 1 ];; reboot) echo rebooted >> "'"$stubs"'/log";; esac'

run_case() {
  local status=$1 active=$2 expect=$3
  rm -f "$stubs/log"
  mkstub bless "echo $status"
  TARGET_ACTIVE=$active bash "$script"
  if [ "$expect" = reboot ]; then
    grep -q rebooted "$stubs/log" || { echo "case $status/$active: expected reboot"; exit 1; }
  else
    [ ! -e "$stubs/log" ] || { echo "case $status/$active: unexpected reboot"; exit 1; }
  fi
  echo "case status=$status active=$active -> $expect ok"
}

run_case indeterminate 0 reboot
run_case indeterminate 1 none
run_case good 0 none
run_case clean 0 none
run_case bad 0 none
echo "all boot-health-timeout cases passed"
