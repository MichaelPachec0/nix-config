# HM wiring for the Quickshell lock: the Nix-owned config seam (fail-open flag +
# fallback image), the dev escape-hatch helper, and the watchdog. The QML/PAM
# live elsewhere (task-bar/lock, features/nixos/auth/pam).
{ config, lib, pkgs, ... }:
let
  # Single source of truth for the dev escape hatch (see the option below). Gates
  # the QML startup-escape (via config.json), the watchdog unit, and the Hyprland
  # recovery keybind (hyprland.nix reads config.quickshellLock.failOpenOnCrash).
  cfg = config.quickshellLock;

  lockEscape = pkgs.writeShellApplication {
    name = "lock-escape";
    runtimeInputs = [ pkgs.quickshell pkgs.procps pkgs.coreutils ];
    text = builtins.readFile ./quickshell/task-bar/lock/lock-escape.sh;
  };
in {
  options.quickshellLock.failOpenOnCrash = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Dev fail-open escape hatch for the Quickshell lock: gates the QML
      startup-escape behavior (via quickshell-lock/config.json), the watchdog
      user service, and the Hyprland recovery keybind (Super+Ctrl+Alt+u). ON for
      the MVP + idle work; flip to false at v2 (keybind/watchdog/helper stay
      flag-guarded in the tree, not deleted).
    '';
  };

  config = {
    home.packages = [ lockEscape ];

    # Config seam the QML LockConfig FileView reads. Outside ~/.config/quickshell
    # (the repo symlink) so it never dirties the repo -- mirrors quickshell-idle.
    xdg.configFile."quickshell-lock/config.json".text = builtins.toJSON {
      failOpenOnCrash = cfg.failOpenOnCrash;
      fallbackImage = "${config.home.homeDirectory}/.local/share/lockscreen.png";
    };

    # Watchdog: quickshell is exec'd by Hyprland (not a supervised unit), so a
    # tiny poll detects "locked marker present but quickshell dead" and runs the
    # escape. Only active while the dev hatch is on.
    systemd.user.services.qs-lock-watchdog = lib.mkIf cfg.failOpenOnCrash {
      Unit.Description = "Dev escape hatch: recover a stranded Quickshell lock";
      Service = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "qs-lock-watchdog" ''
          marker="''${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-lock.locked"
          while true; do
            # `-f 'quickshell -c task-bar'`, not `-x quickshell`: the wrapped bar's
            # comm is `.quickshell-wra`, so `-x quickshell` matches nothing even while
            # the bar is alive -- which would make this watchdog false-detect "dead" and
            # unlock every legitimate lock. Match the full command line instead.
            if [ -e "$marker" ] && ! ${pkgs.procps}/bin/pgrep -f 'quickshell -c task-bar' >/dev/null; then
              ${lockEscape}/bin/lock-escape
              rm -f "$marker"
            fi
            sleep 2
          done
        '';
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
