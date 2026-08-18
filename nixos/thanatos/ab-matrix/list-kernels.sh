#!/usr/bin/env bash
# List the cachyos kernel variants this flake actually exposes, optionally
# filtered. Authoritative, unlike the upstream README.
set -eu
filter="${1:-}"
flake="${2:-/home/michael/nix-config}"
nix eval --impure --json --expr \
  "builtins.attrNames (builtins.getFlake \"${flake}\").inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux" |
  tr ',' '\n' | tr -d '[]"' | grep -i "${filter}" | sort
