# boot-fallback-alert: notice that systemd-boot fell back to an older
# generation, halt further upgrades, tell the owner once.
#
# Runs after network-online on every boot. A fallback leaves an ESP entry
# named nixos-<hash>+0-<n>.conf (tries exhausted) whose `version Generation
# <n>` is newer than the generation now booted. When found: write the halt
# file that nixos-upgrade.service checks (otherwise the same broken
# configuration is rebuilt and rebooted into every night), send one ntfy
# message with the last failed boot's errors, and remember the newest bad
# generation so the same fallback is not re-sent on every boot.
#
# Env: ENTRIES_DIR (/boot/loader/entries), PROFILES_DIR
#      (/nix/var/nix/profiles), BOOTED_SYSTEM (/run/booted-system), STATE_DIR
#      (/var/lib/auto-upgrade), NTFY_SEND (ntfy-send), JOURNALCTL
#      (journalctl), HOSTNAME_CMD (hostname).
set -euo pipefail

entries=${ENTRIES_DIR:-/boot/loader/entries}
profiles=${PROFILES_DIR:-/nix/var/nix/profiles}
booted_link=${BOOTED_SYSTEM:-/run/booted-system}
state=${STATE_DIR:-/var/lib/auto-upgrade}
ntfy=${NTFY_SEND:-ntfy-send}
journalctl_cmd=${JOURNALCTL:-journalctl}
hostname_cmd=${HOSTNAME_CMD:-hostname}

booted=$(readlink -f "$booted_link")
booted_gen=""
for link in "$profiles"/system-*-link; do
  [ -e "$link" ] || continue
  if [ "$(readlink -f "$link")" = "$booted" ]; then
    n=${link##*/system-}
    booted_gen=${n%-link}
  fi
done
if [ -z "$booted_gen" ]; then
  echo "boot-fallback-alert: booted system $booted is not a profile generation; nothing to compare"
  exit 0
fi

bad_gens=""
newest=0
for f in "$entries"/nixos-*+0-*.conf; do
  [ -e "$f" ] || continue
  gen=$(sed -n 's/^version Generation \([0-9][0-9]*\) .*/\1/p' "$f" | head -n 1)
  [ -n "$gen" ] || continue
  if [ "$gen" -gt "$booted_gen" ]; then
    bad_gens="$bad_gens $gen"
    [ "$gen" -gt "$newest" ] && newest=$gen
  fi
done
bad_gens=${bad_gens# }
if [ -z "$bad_gens" ]; then
  echo "boot-fallback-alert: no bad generation newer than booted generation $booted_gen"
  exit 0
fi

mkdir -p "$state"
if [ -e "$state/alerted" ] && [ "$(cat "$state/alerted")" = "$newest" ]; then
  echo "boot-fallback-alert: fallback from generation $newest already reported"
  exit 0
fi

echo "$newest" > "$state/halted"
host=$("$hostname_cmd")
{
  echo "host: $host"
  echo "bad generation(s): $bad_gens"
  echo "booted generation: $booted_gen ($booted)"
  echo
  echo "Nightly upgrades are halted. After fixing the configuration:"
  echo "  rm /var/lib/auto-upgrade/halted"
  echo
  echo "errors from the last failed boot:"
  "$journalctl_cmd" -b -1 -p err -n 30 --no-pager || echo "(journal for the previous boot unavailable)"
} | "$ntfy" "$host: boot fallback to generation $booted_gen" high rotating_light
echo "$newest" > "$state/alerted"
echo "boot-fallback-alert: reported fallback from generation $newest, upgrades halted"
