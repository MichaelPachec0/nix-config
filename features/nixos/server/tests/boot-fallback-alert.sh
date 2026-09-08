#!/usr/bin/env bash
# Runs scripts/boot-fallback-alert.sh against a fake ESP entries dir, fake
# profile links, a stub ntfy-send and a stub journalctl.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/boot-fallback-alert.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/entries" "$tmp/profiles" "$tmp/state" "$tmp/gen1" "$tmp/gen2" "$tmp/gen3"
ln -s "$tmp/gen1" "$tmp/profiles/system-1-link"
ln -s "$tmp/gen2" "$tmp/profiles/system-2-link"
ln -s "$tmp/gen3" "$tmp/profiles/system-3-link"
ln -s "$tmp/gen1" "$tmp/booted"

entry() { printf 'title NixOS\nversion Generation %s NixOS 26.05, Linux Kernel 6.12, built on 2026-09-08\nlinux /EFI/nixos/x.efi\n' "$2" > "$tmp/entries/nixos-$1$3.conf"; }
printf '#!/usr/bin/env bash\n{ echo "title=$1 prio=$2 tags=$3"; cat; } > "%s/alert"\n' "$tmp" > "$tmp/ntfy"; chmod +x "$tmp/ntfy"
printf '#!/usr/bin/env bash\necho "journal: $*"\n' > "$tmp/journalctl"; chmod +x "$tmp/journalctl"
printf '#!/usr/bin/env bash\necho testhost\n' > "$tmp/hostname"; chmod +x "$tmp/hostname"

export ENTRIES_DIR="$tmp/entries" PROFILES_DIR="$tmp/profiles" BOOTED_SYSTEM="$tmp/booted" \
       STATE_DIR="$tmp/state" NTFY_SEND="$tmp/ntfy" JOURNALCTL="$tmp/journalctl" HOSTNAME_CMD="$tmp/hostname"

echo "case 1: no bad entries -> nothing"
entry aaa 1 ""
bash "$script"
[ ! -e "$tmp/alert" ] && [ ! -e "$tmp/state/halted" ] || { echo "case 1: unexpected alert"; exit 1; }

echo "case 2: bad entry older than booted -> nothing"
rm -f "$tmp/booted"; ln -s "$tmp/gen3" "$tmp/booted"
entry bbb 2 "+0-2"
bash "$script"
[ ! -e "$tmp/alert" ] || { echo "case 2: unexpected alert"; exit 1; }

echo "case 3: bad entry newer than booted -> halt + alert"
rm -f "$tmp/booted"; ln -s "$tmp/gen1" "$tmp/booted"
entry ccc 3 "+0-2"
bash "$script"
grep -q '^title=testhost: boot fallback to generation 1 prio=high tags=rotating_light$' "$tmp/alert"
grep -q 'bad generation(s): 2 3' "$tmp/alert"
grep -q 'booted generation: 1' "$tmp/alert"
grep -q 'journal: -b -1 -p err -n 30 --no-pager' "$tmp/alert"
grep -q 'rm /var/lib/auto-upgrade/halted' "$tmp/alert"
[ "$(cat "$tmp/state/halted")" = 3 ]
[ "$(cat "$tmp/state/alerted")" = 3 ]

echo "case 4: same fallback on the next boot -> no second alert"
rm -f "$tmp/alert"
bash "$script"
[ ! -e "$tmp/alert" ] || { echo "case 4: duplicate alert"; exit 1; }

echo "case 5: a newer bad generation alerts again"
mkdir -p "$tmp/gen4"; ln -s "$tmp/gen4" "$tmp/profiles/system-4-link"
entry ddd 4 "+0-2"
bash "$script"
grep -q 'bad generation(s): 2 3 4' "$tmp/alert"
[ "$(cat "$tmp/state/alerted")" = 4 ]

echo "case 6: booted system is not a profile generation -> nothing"
rm -f "$tmp/booted" "$tmp/alert"; ln -s "$tmp" "$tmp/booted"
bash "$script"
[ ! -e "$tmp/alert" ] || { echo "case 6: unexpected alert"; exit 1; }
echo "all boot-fallback-alert cases passed"
