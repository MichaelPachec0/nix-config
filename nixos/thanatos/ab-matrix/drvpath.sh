#!/usr/bin/env bash
# Print the derivation path of the ncspot load for a given marker.
# Used to prove that distinct markers really do force distinct builds.
set -eu
marker="${1:?usage: drvpath.sh MARKER [FLAKE]}"
flake="${2:-/home/michael/nix-config}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nix eval --impure --raw --expr \
  "builtins.unsafeDiscardStringContext (import ${here}/ncspot-load.nix { flake = \"${flake}\"; marker = \"${marker}\"; }).drvPath"
