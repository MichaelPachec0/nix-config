# Cache-busting build load for the desktop-latency matrix.
#
# The matrix needs a compile that is REPRODUCIBLE in shape but never served
# from cache: every cell must do the same work, and a store hit would make a
# cell finish instantly and measure nothing. Adding an attribute to the
# derivation changes its hash, so the whole Rust compile reruns.
#
# ncspot is a good load for the question being asked. It is a real Rust build
# (rustc + LLVM, heavily parallel, memory-hungry, lots of small file I/O), it
# lives in this flake already, and it lands in the 10-20 minute range that makes
# a cell long enough to create sustained pressure without blowing the budget.
#
# NOT WIRED INTO ANY HOST, deliberately. This is a benchmark artifact; putting a
# cache-buster into a host's package set would mean every rebuild of that host
# recompiles ncspot for no reason.
#
# The marker only perturbs the compile, not the fetch: cargoDeps is a
# fixed-output derivation keyed on the lockfile, so vendored crates stay cached
# and the measured work is compilation rather than network.
#
# Usage (impure, because the marker has to vary per cell):
#
#   nix build --impure --no-link --expr \
#     "import ./ncspot-load.nix { flake = \"/home/michael/nix-config\"; marker = \"$(date +%s)\"; }"
#
# Verify two markers really produce two derivations before trusting a run:
#
#   nix eval --impure --raw --expr 'builtins.unsafeDiscardStringContext
#     (import ./ncspot-load.nix { flake = "..."; marker = "a"; }).drvPath'
{
  flake,
  marker,
  system ? builtins.currentSystem,
}: let
  f = builtins.getFlake (toString flake);
  base = f.inputs.ncspot.packages.${system}.ncspot;
in
  base.overrideAttrs (old: {
    # Any new attribute changes the derivation hash. A plain env var is used
    # rather than a source patch because it cannot alter what is compiled --
    # only whether the result is already in the store. A patch that edited a
    # source file would change the work itself between markers, which would
    # make cells incomparable.
    AB_MATRIX_MARKER = marker;
  })
