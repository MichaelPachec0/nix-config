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
# unless wine-fonts is present exactly once under an extendModules override
# forcing backend = "regreet" and exactly twice under one forcing
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
      # BOTH arms force the backend explicitly. This used to read the host
      # as-configured for the "off" arm, which silently stopped testing
      # anything the moment thanatos actually cut over to qsGreeter: both
      # arms then evaluated the same config and the counts agreed for the
      # wrong reason. What is being checked is the mkIf gate, so neither arm
      # may depend on which backend the host happens to run today.
      regreetCfg = (flake.nixosConfigurations.thanatos.extendModules {
        modules = [{ services.graphicalLogin.backend = lib.mkForce "regreet"; }];
      }).config;
      qsCfg = (flake.nixosConfigurations.thanatos.extendModules {
        modules = [{ services.graphicalLogin.backend = lib.mkForce "qsGreeter"; }];
      }).config;
  in {
    hostBackend = flake.nixosConfigurations.thanatos.config.services.graphicalLogin.backend;
    defaultWineFontsCount = countWine regreetCfg;
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
  echo "FAIL: expected exactly 1 wine-fonts entry with backend = regreet"
  echo "      (the one nyx/configuration.nix adds unconditionally for Wine itself;"
  echo "      a second would mean this module's fonts.packages escaped its mkIf)"
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
