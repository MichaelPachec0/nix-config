#!/usr/bin/env bash
# Runs scripts/boot-health.sh against stubbed ip / ss / zerotier-cli.
# Usage: tests/boot-health.sh   (from features/nixos/server)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/boot-health.sh"
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT

mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$stubs/$1"; chmod +x "$stubs/$1"; }

export PATH="$stubs:$PATH" BOOT_HEALTH_STEP=0 BOOT_HEALTH_SSH_PORT=22

echo "case 1: everything healthy, zerotier configured"
mkstub ip 'echo "default via 10.0.0.1 dev eth0"'
mkstub ss 'echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*"'
mkstub zerotier-cli 'echo "200 listnetworks 565799d8f65ab6a3 net aa:bb OK PRIVATE zt0 172.30.0.5/24"'
BOOT_HEALTH_ZT_NETWORK=565799d8f65ab6a3 bash "$script"

echo "case 2: healthy, zerotier check skipped when unset"
mkstub zerotier-cli 'exit 99'
BOOT_HEALTH_ZT_NETWORK= bash "$script"

echo "case 3: no default route fails"
mkstub ip 'true'
if BOOT_HEALTH_ZT_NETWORK= bash "$script"; then echo "expected failure"; exit 1; fi

echo "case 4: sshd not listening fails"
mkstub ip 'echo "default via 10.0.0.1 dev eth0"'
mkstub ss 'true'
if BOOT_HEALTH_ZT_NETWORK= bash "$script"; then echo "expected failure"; exit 1; fi

echo "case 5: zerotier not OK fails"
mkstub ss 'echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*"'
mkstub zerotier-cli 'echo "200 listnetworks 565799d8f65ab6a3 net aa:bb REQUESTING_CONFIGURATION PRIVATE zt0 -"'
if BOOT_HEALTH_ZT_NETWORK=565799d8f65ab6a3 bash "$script"; then echo "expected failure"; exit 1; fi

echo "case 6: transient failure then success passes (retry loop)"
mkstub zerotier-cli 'f='"$stubs"'/zt-count; c=$(cat "$f" 2>/dev/null || echo 0); echo $((c+1)) > "$f"; if [ "$c" -ge 2 ]; then echo "200 listnetworks 565799d8f65ab6a3 net aa:bb OK PRIVATE zt0 172.30.0.5/24"; else echo "200 listnetworks 565799d8f65ab6a3 net aa:bb REQUESTING_CONFIGURATION PRIVATE zt0 -"; fi'
BOOT_HEALTH_ZT_NETWORK=565799d8f65ab6a3 bash "$script"

echo "all boot-health cases passed"
