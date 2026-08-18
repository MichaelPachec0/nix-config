#!/usr/bin/env bash
# Show what a given marker would build vs fetch, without building it.
set -eu
marker="${1:?usage: dryrun.sh MARKER [FLAKE]}"
flake="${2:-/home/michael/nix-config}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nix build --dry-run --impure --no-link --expr \
  "import ${here}/ncspot-load.nix { flake = \"${flake}\"; marker = \"${marker}\"; }"
