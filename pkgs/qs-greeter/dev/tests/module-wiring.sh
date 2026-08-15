#!/usr/bin/env bash
# F6/F8/F9/F10 regression coverage for the Nix module itself (as opposed to
# the QML, which the other suites cover):
#   F6  QSG_STATE_FILE was read by GreeterState.qml but never set by this
#       module -- silently falling back to its own hardcoded default -- and
#       the tmpfiles `d` rule hardcoded /var/lib/qs-greeter while userFile
#       was derived from an option, so pointing userFile elsewhere left
#       tmpfiles creating the wrong parent. userFile and the new stateFile
#       option now both derive from programs.qsGreeter.dataDir, and so does
#       the tmpfiles rule; this builds with dataDir OVERRIDDEN to a
#       non-default path and confirms all three actually moved together.
#   F8  programs.qsGreeter had no equivalent of programs.regreet.settings.env
#       for injecting environment into the launched session; QSG_SESSION_ENV
#       (programs.qsGreeter.sessionEnv) now defaults to the same
#       WLR_DRM_NO_MODIFIERS=1 the regreet backend carries.
#   F9  /var/lib/qs-greeter was not in thanatos's impermanence directory
#       list, so the writable settings tier and last-user state were wiped
#       every boot; confirms it is now included exactly when
#       programs.qsGreeter.enable is true and excluded when it is false.
#
# Builds the REAL wrapperPackage derivation (nix build, allowed under this
# fix's own constraints, same pattern crashloop.sh already uses) and reads
# its rendered script, rather than trying to eval a `text` attribute that
# writeShellApplication does not expose after packaging as a queryable
# output.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

pass=0
total=0
check() {
  local name="$1" got="$2" want="$3"
  total=$((total + 1))
  if [ "$got" = "$want" ]; then pass=$((pass + 1))
  else echo "MODULE-WIRING-TEST CASE FAIL: $name got=$got want=$want"; fi
}
ok() {
  local name="$1" count="$2"
  total=$((total + 1))
  if [ "$count" -ge 1 ]; then pass=$((pass + 1))
  else echo "MODULE-WIRING-TEST CASE FAIL: $name (0 matches)"; fi
}

echo "building wrapperPackage under an overridden dataDir..." >&2
launch_out="$(nix build --impure --no-link --print-out-paths --expr \
  'let f = (builtins.getFlake (toString "'"$root"'"));
       c = (f.nixosConfigurations.thanatos.extendModules { modules = [({ lib, ... }: {
         services.graphicalLogin.backend = lib.mkForce "qsGreeter";
         services.graphicalLogin.enable = lib.mkForce true;
         programs.qsGreeter.dataDir = "/var/lib/qs-greeter-custom";
         # mkForce because nyx/configuration.nix (shared by every host,
         # including the thanatos this evaluates) now sets primaryOutput for
         # real. Without it this arm measures the HOST value and the
         # null-to-empty-string mapping below goes untested -- which is
         # exactly what happened when the greeter was cut over.
         programs.qsGreeter.primaryOutput = lib.mkForce null;
       })]; }).config;
   in c.programs.qsGreeter.wrapperPackage' 2>/dev/null | tail -n1)"

if [ -z "$launch_out" ] || [ ! -x "$launch_out/bin/qs-greeter-launch" ]; then
  echo "MODULE-WIRING-TEST FAIL: nix build of wrapperPackage did not produce a binary"
  exit 1
fi
script="$(cat "$launch_out/bin/qs-greeter-launch")"

ok "userFileMovesWithDataDir" \
  "$(echo "$script" | grep -c '^export QSG_USER_FILE=/var/lib/qs-greeter-custom/settings.json$')"
ok "stateFileMovesWithDataDir" \
  "$(echo "$script" | grep -c '^export QSG_STATE_FILE=/var/lib/qs-greeter-custom/state.json$')"
ok "sessionEnvDefaultsToWlrNoModifiers" \
  "$(echo "$script" | grep -c 'QSG_SESSION_ENV=.*WLR_DRM_NO_MODIFIERS.*1')"
# null must reach the wrapper as an empty string, which is what shell.qml
# treats as "no output named, fall back to whichever Quickshell lists
# first". The forced null above is what makes this a real assertion rather
# than a reading of whatever the host is configured with.
ok "primaryOutputNullBecomesEmptyString" \
  "$(echo "$script" | grep -c "^export QSG_PRIMARY_OUTPUT=''$")"

echo "checking tmpfiles + persistence wiring..." >&2
result="$(nix eval --impure --json --expr \
  'let f = (builtins.getFlake (toString "'"$root"'"));
       c = (f.nixosConfigurations.thanatos.extendModules { modules = [{
         services.graphicalLogin.backend = "qsGreeter";
         services.graphicalLogin.enable = true;
         programs.qsGreeter.dataDir = "/var/lib/qs-greeter-custom";
         programs.qsGreeter.group = "qsgreeter";
       }]; }).config;
       lib = f.nixosConfigurations.thanatos.pkgs.lib;
       persistOn = import "'"$root"'/nixos/thanatos/impermanence.nix" {
         inherit lib;
         config = { programs.qsGreeter.enable = true;
                    services.hardware.bolt.enable = false;
                    services.upower.enable = false; };
       };
       persistOff = import "'"$root"'/nixos/thanatos/impermanence.nix" {
         inherit lib;
         config = { programs.qsGreeter.enable = false;
                    services.hardware.bolt.enable = false;
                    services.upower.enable = false; };
       };
   in {
     tmpfilesDirRuleMoved = builtins.elem
       "d /var/lib/qs-greeter-custom 0755 greeter qsgreeter - -"
       c.systemd.tmpfiles.rules;
     persistIncludedWhenEnabled = builtins.elem "/var/lib/qs-greeter"
       persistOn.environment.persistence."/persist".directories;
     persistExcludedWhenDisabled = !(builtins.elem "/var/lib/qs-greeter"
       persistOff.environment.persistence."/persist".directories);
   }' 2>/dev/null)"

echo "MODULE-WIRING-EVAL RESULT: $result"
if [ -z "$result" ]; then
  echo "MODULE-WIRING-TEST FAIL: eval produced no result (crashed or errored)"
  exit 1
fi

check "tmpfilesDirRuleMovesWithDataDir" "$(echo "$result" | jq -r '.tmpfilesDirRuleMoved')" "true"
check "persistDirectoryIncludedWhenEnabled" "$(echo "$result" | jq -r '.persistIncludedWhenEnabled')" "true"
check "persistDirectoryExcludedWhenDisabled" "$(echo "$result" | jq -r '.persistExcludedWhenDisabled')" "true"

if [ "$pass" = "$total" ]; then
  echo "MODULE-WIRING-TEST PASS $pass/$total"
else
  echo "MODULE-WIRING-TEST FAIL $pass/$total"
  exit 1
fi
