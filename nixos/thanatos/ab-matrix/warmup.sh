#!/usr/bin/env bash
# Warm up the ncspot build load and time both phases.
#
# Phase 1 (warm-up) builds the ~120 intermediate crate derivations that were
# never realised locally, because the cached ncspot output meant nix never
# needed them. This cost is paid once and then cached forever.
#
# Phase 2 measures the STEADY-STATE cost: a second marker, with those crates now
# in the store, rebuilds only the final ncspot derivation. That number is the
# per-cell cost the matrix has to be sized around, and it is the only one that
# matters for planning.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flake="${FLAKE:-/home/michael/nix-config}"
log="${LOG:-$here/../../../.ab-matrix/warmup.log}"
mkdir -p "$(dirname "$log")"

build() { # <marker>
  nix build --impure --no-link --print-build-logs \
    --expr "import ${here}/ncspot-load.nix { flake = \"${flake}\"; marker = \"$1\"; }"
}

{
  echo "=== warm-up started $(date -Is) ==="
  t0=$(date +%s)
  build warmup-1 >/dev/null 2>&1
  rc1=$?
  t1=$(date +%s)
  echo "phase1 (warm-up, ~120 crates + ncspot): $((t1 - t0))s  rc=$rc1"

  echo "=== steady-state started $(date -Is) ==="
  build steady-1 >/dev/null 2>&1
  rc2=$?
  t2=$(date +%s)
  echo "phase2 (steady state, ncspot only):     $((t2 - t1))s  rc=$rc2"

  echo "=== done $(date -Is) ==="
  echo "PER-CELL COST = phase2 = $((t2 - t1))s"
} 2>&1 | tee "$log"
