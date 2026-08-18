#!/usr/bin/env bash
# Dry-run the UNMODIFIED ncspot, for comparison against a marker build.
# If the plain package also reports ~119 derivations to build, those are
# genuinely-missing crates that will be cached after one warm-up build, and only
# the final ncspot derivation rebuilds per marker.
set -eu
flake="${1:-/home/michael/nix-config}"
nix build --dry-run --impure --no-link --expr \
  "(builtins.getFlake \"${flake}\").inputs.ncspot.packages.\${builtins.currentSystem}.ncspot"
