{
  config,
  pkgs,
  lib,
  ...
}: let
  # The report itself lives in system-diff.sh so it can be run and shellchecked
  # standalone: `nixos-system-diff /nix/var/nix/profiles/system-{165,166}-link`.
  nixos-system-diff = pkgs.writeShellApplication {
    name = "nixos-system-diff";
    runtimeInputs = with pkgs; [
      config.nix.package
      coreutils
      diffutils
      findutils
      gawk
      gnugrep
      gnused
      jq
      nvd
    ];
    text = ''
      # nvd and `nix store diff-closures` both need a nix binary directory, and
      # the activation script runs with a PATH we do not control.
      NIX_BIN_DIR=''${NIX_BIN_DIR:-${config.nix.package}/bin}
    ''
    + builtins.readFile ./system-diff.sh;
  };
in {
  environment.systemPackages = [nixos-system-diff];

  # Record the lock the generation was built from, so the report can say which
  # flake inputs moved between two generations. Nothing else reads this file;
  # generations built before this landed simply have no flake.lock and the
  # report says so instead of guessing.
  system.extraSystemBuilderCmds = ''
    cp ${../../../flake.lock} $out/flake.lock
  '';

  # Replaces the old one-line `nvd diff | tee /etc/gradientos-changelog` hook.
  # supportsDryActivation matters: with it, `nixos-rebuild dry-activate` prints
  # the whole report, which is the point of expanding it. The script writes no
  # log in that mode.
  system.activationScripts.diff = {
    supportsDryActivation = true;
    text = ''
      if [[ -e /run/current-system ]]; then
        if [[ "''${NIXOS_ACTION:-}" == "dry-activate" ]]; then
          export NIXOS_DIFF_NO_WRITE=1
        fi
        # Forced on: nixos-rebuild-ng runs activation under
        # `systemd-run --pipe`, so stdout is never a tty and auto would always
        # pick plain text. The unit forwards only a fixed env allowlist, so a
        # NIXOS_DIFF_COLOR from the calling shell cannot reach this point
        # either. nom passes the escapes through as is; the saved log is
        # stripped.
        NIXOS_DIFF_COLOR=always ${lib.getExe nixos-system-diff} /run/current-system "$systemConfig" || true
      fi
    '';
  };
}
