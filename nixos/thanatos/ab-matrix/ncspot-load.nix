# Cache-busting build load for the desktop-latency matrices.
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
# TAKES A LIST, and that is the important part. Each `nix build --expr` that
# calls builtins.getFlake on this repo pays a FULL evaluation of nix-config and
# nixpkgs, because a dirty git tree has no eval-cache fingerprint and so is
# never cached. Measured: four concurrent evaluations were still running after
# 150 seconds without a single rustc process existing, so a 45s settle plus a
# 210s window recorded four nix evaluations rather than four Rust builds, and
# every cell reported builds_alive=0. Evaluating every marker for the whole run
# in ONE invocation moves that cost out of the measured window entirely and
# makes each cell start compiling immediately.
#
# Usage:
#
#   nix eval --impure --json --expr \
#     'map (d: d.drvPath) (import ./ncspot-load.nix {
#        flake = "/home/michael/nix-config"; markers = ["a" "b"]; })'
#
# Forcing drvPath instantiates each derivation into the store, so the paths it
# prints can then be built directly with `nix build /nix/store/....drv^*` and no
# further evaluation.
{
  flake,
  markers,
  system ? builtins.currentSystem,
}: let
  f = builtins.getFlake (toString flake);
  base = f.inputs.ncspot.packages.${system}.ncspot;
in
  map (
    marker:
    # Any new attribute changes the derivation hash. A plain env var is used
    # rather than a source patch because it cannot alter what is compiled --
    # only whether the result is already in the store. A patch that edited a
    # source file would change the work itself between markers, which would
    # make cells incomparable.
      base.overrideAttrs (_old: {
        AB_MATRIX_MARKER = marker;
      })
  )
  markers
