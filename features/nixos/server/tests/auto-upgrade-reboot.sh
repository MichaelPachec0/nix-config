#!/usr/bin/env bash
# Runs scripts/auto-upgrade-reboot.sh with fake booted/staged links and a
# fake clock. It must reboot only when a different generation is staged and
# the time is inside the window (including a window across midnight).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/auto-upgrade-reboot.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/genA" "$tmp/genB"
ln -s "$tmp/genA" "$tmp/booted"
printf '#!/usr/bin/env bash\necho "shutdown $*" >> "%s/log"\n' "$tmp" > "$tmp/shutdown"; chmod +x "$tmp/shutdown"
export BOOTED_SYSTEM="$tmp/booted" SHUTDOWN="$tmp/shutdown"

run_case() {
  local staged=$1 now=$2 lower=$3 upper=$4 expect=$5
  rm -f "$tmp/log" "$tmp/profile"; ln -s "$tmp/$staged" "$tmp/profile"
  SYSTEM_PROFILE="$tmp/profile" AUTO_UPGRADE_NOW="$now" WINDOW_LOWER="$lower" WINDOW_UPPER="$upper" bash "$script"
  if [ "$expect" = reboot ]; then
    grep -q '^shutdown -r +1' "$tmp/log" || { echo "case $*: expected reboot"; exit 1; }
  else
    [ ! -e "$tmp/log" ] || { echo "case $*: unexpected reboot"; exit 1; }
  fi
  echo "case staged=$staged now=$now window=$lower-$upper -> $expect ok"
}

run_case genA 03:30 03:00 05:00 none      # nothing staged
run_case genB 03:30 03:00 05:00 reboot    # staged, in window
run_case genB 06:00 03:00 05:00 none      # staged, outside window
run_case genB 02:59 03:00 05:00 none      # boundary below
run_case genB 23:30 23:00 05:00 reboot    # window across midnight, evening side
run_case genB 04:00 23:00 05:00 reboot    # window across midnight, morning side
run_case genB 12:00 23:00 05:00 none      # across midnight, daytime
run_case genB 03:00 03:00 05:00 none      # exactly lower
run_case genB 05:00 03:00 05:00 none      # exactly upper
run_case genB 23:00 23:00 05:00 none      # exactly lower, window across midnight
run_case genB 05:00 23:00 05:00 none      # exactly upper, window across midnight
echo "all auto-upgrade-reboot cases passed"
