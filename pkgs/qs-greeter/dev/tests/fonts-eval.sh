#!/usr/bin/env bash
# Confirms `fonts.packages = [pkgs.winePackages.fonts];` in
# features/nixos/login/qs-greeter.nix actually evaluates and is correctly
# gated behind `config = lib.mkIf cfg.enable { ... }` -- present only when
# services.graphicalLogin.backend = "qsGreeter", absent (falling back to
# whatever else the host's fonts.packages already carries) otherwise.
# `nix eval` only forces attribute values, never builds/realizes a
# derivation, so this is safe to run unasked (unlike a nixos-rebuild).
#
# Fails loudly: prints the raw eval result either way, then exits nonzero
# unless wine-fonts is present exactly once under the default backend and
# exactly twice under an extendModules override that flips backend to
# "qsGreeter" (thanatos's shared nyx/configuration.nix already lists
# winePackages.fonts once, unconditionally, for actual Wine use --
# confirmed by inspection before writing this check, so "twice" and not
# "once" is the correct signal that this module's own fonts.packages line
# fired, not just the pre-existing entry).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# This nixpkgs pin's store link-farm is already near its hardlink ceiling
# (an unrelated, pre-existing "has maximum number of links" condition, not
# something this check triggers), so a full nixosConfigurations eval can
# print tens of thousands of warning lines -- enough that piping it through
# a shell *variable* (`out="$(...)"`; `echo "$out" | grep ...`) tripped
# "Argument list too long" on this host. Writing straight to a file and
# grepping the file sidesteps that regardless of its root cause.
(cd "$root" && nix eval --impure --expr '
  let flake = builtins.getFlake (toString "'"$root"'");
      lib = flake.nixosConfigurations.thanatos.pkgs.lib;
      countWine = cfg: lib.length (builtins.filter
        (p: (p.pname or p.name) == "wine-fonts") cfg.fonts.packages);
      defCfg = flake.nixosConfigurations.thanatos.config;
      qsCfg = (flake.nixosConfigurations.thanatos.extendModules {
        modules = [{ services.graphicalLogin.backend = "qsGreeter"; }];
      }).config;
  in {
    defaultBackend = defCfg.services.graphicalLogin.backend;
    defaultWineFontsCount = countWine defCfg;
    qsGreeterWineFontsCount = countWine qsCfg;
  }
' >"$tmp" 2>&1) || true

grep -v '^"/nix/store/.links/' "$tmp" || true

result_line="$(grep -o '{ [^}]*}' "$tmp" | tail -1)"

if [ -z "$result_line" ]; then
  echo "FAIL: fonts-eval produced no result attrset (eval crashed or errored)"
  exit 1
fi

echo "FONTS-EVAL RESULT: $result_line"

overall=0

if ! echo "$result_line" | grep -q 'defaultWineFontsCount = 1;'; then
  echo "FAIL: expected exactly 1 wine-fonts entry with the default backend"
  overall=1
fi

if ! echo "$result_line" | grep -q 'qsGreeterWineFontsCount = 2;'; then
  echo "FAIL: expected exactly 2 wine-fonts entries with backend = qsGreeter"
  overall=1
fi

if [ "$overall" -eq 0 ]; then
  echo "FONTS-EVAL PASS"
fi

exit "$overall"
