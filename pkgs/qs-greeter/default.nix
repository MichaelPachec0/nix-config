{
  lib,
  pkgs,
  stdenvNoCC,
}:
let
  # writeShellApplication installs exactly one script per derivation
  # (bin/<name>), so qs-greeter-run.sh's own "sessions.json builder" sibling
  # cannot live next to it once packaged -- its "$(dirname "$0")/sessions-parse.sh"
  # fallback only works when run straight out of the repo. sessionsParse below
  # is packaged separately for the same reason, and features/nixos/login/qs-greeter.nix
  # points QSG_PARSE at it explicitly rather than relying on dirname.
  runWrapper = pkgs.writeShellApplication {
    name = "qs-greeter-run";
    runtimeInputs = with pkgs; [jq coreutils findutils gnused gawk foot sway systemd quickshell];
    text = builtins.readFile ./wrapper/qs-greeter-run.sh;
  };

  sessionsParse = pkgs.writeShellApplication {
    name = "sessions-parse";
    runtimeInputs = with pkgs; [jq coreutils findutils gnused gawk];
    text = builtins.readFile ./wrapper/sessions-parse.sh;
  };
in
stdenvNoCC.mkDerivation {
  pname = "qs-greeter";
  version = "0.1.0";
  src = ./greeter;

  # dev/ is a sibling of greeter/, so it is structurally excluded: `src` points
  # at greeter/ only. The mock greetd backend must never exist on a deployed
  # system -- an env-gated fake auth path would be one stray EnvironmentFile
  # away from a login bypass.
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/greeter"
    cp -r ./. "$out/greeter/"
    runHook postInstall
  '';

  # Exposes the wrapper binaries alongside the QML tree so the NixOS module
  # (features/nixos/login/qs-greeter.nix) can reference cfg.package.wrapper /
  # cfg.package.sessionsParse instead of re-deriving writeShellApplication
  # calls itself. Package-building logic (runtimeInputs, shellcheck) stays
  # here with the scripts it wraps; the module only decides which QSG_* env
  # vars to feed the result -- that split is policy vs. mechanism.
  passthru = {
    wrapper = runWrapper;
    inherit sessionsParse;
  };

  meta = {
    description = "Quickshell greetd greeter (QML tree)";
    platforms = lib.platforms.linux;
  };
}
