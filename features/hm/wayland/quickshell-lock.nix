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

  # Single source of truth for the activate-linux watermark: hyprland.nix +
  # sway.nix build the activate-linux CLI invocation from these fields, and
  # this module writes them into config.json below for LockConfig.qml (the
  # lock's under-lock replica) to read -- so the desktop overlay and the lock
  # replica never drift out of sync. activate-linux's internal cairo layout
  # constants (text x=20, baseline offsets, 24/16px fonts, DejaVu Sans) are
  # fixed by its source, not its CLI, so they stay hardcoded in the QML.
  options.quickshellLock.watermark = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Render the activate-linux-style watermark (bottom-right) on the desktop overlay AND replicate it on the lock. Single source for both.";
    };
    title = lib.mkOption {
      type = lib.types.str;
      default = "Activate NixOS";
      description = "Watermark title (activate-linux -t).";
    };
    message = lib.mkOption {
      type = lib.types.str;
      default = "Edit configuration.nix to activate NixOS.";
      description = "Watermark subtitle (activate-linux -m).";
    };
    color = lib.mkOption {
      type = lib.types.str;
      default = "1-1-1-0.10";
      description = "r-g-b-a floats, activate-linux -c format; the lock QML parses the same string.";
    };
    width = lib.mkOption {
      type = lib.types.int;
      default = 360;
      description = "Overlay width (activate-linux -x).";
    };
    height = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Overlay height (activate-linux -y).";
    };
  };

  # Backdrop source for the lock surface. "workspace" freezes each output's
  # desktop via ScreencopyView at the instant of locking and blurs that;
  # "wallpaper" blurs the awww wallpaper (the original MVP behaviour). The
  # workspace path falls back to the wallpaper automatically whenever a capture
  # is missing or empty, so "workspace" is never a hard dependency on
  # screencopy being available.
  options.quickshellLock.backdrop.mode = lib.mkOption {
    type = lib.types.enum [ "workspace" "wallpaper" ];
    default = "workspace";
    description = ''
      Lock backdrop source: "workspace" (frozen ScreencopyView of the desktop,
      blurred; falls back to the wallpaper when capture yields nothing) or
      "wallpaper" (blurred awww wallpaper).
    '';
  };

  options.quickshellLock.notifications = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show the notification backlog on the lock.";
    };
    defaultMode = lib.mkOption {
      type = lib.types.enum [ "hidden" "sensitive" "full" ];
      default = "sensitive";
      description = "Default visibility for the 'default' tier (non-trusted, non-private).";
    };
    maxCards = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        Hard ceiling on notification cards before a '+N more' footer.
        0 (the default) means no ceiling: how many cards render is decided
        by the space actually left above the watermark, shrinking when the
        media or weather widgets grow. Set a positive value only to cap the
        list tighter than the available space would.
      '';
    };
    trustedApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "blueman" "blueman-applet" "NetworkManager" "org.freedesktop.*" ];
      description = "App names / desktop-entries (glob, '*' only) whose notifications are full + interactive on the lock.";
    };
    privateApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "App names / desktop-entries (glob) forced to hidden (count-only) on the lock, even when Critical.";
    };
    trustedCategories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "device" "network" "x-systemd*" "hardware" ];
      description = "freedesktop notification categories (glob) treated as trusted.";
    };
  };

  options.quickshellLock.security = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show the security/presence signal column on the lock.";
    };
    ownerText = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Optional "if found" contact line shown on the lock. Anyone who can see
        the lock screen can read it, which is the point -- so it is empty by
        default and opt-in.
      '';
    };
    screencastPoll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Poll PipeWire while locked to detect a screen capture that STARTS during
        the lock. With this off the lock only reports a capture that was already
        running when it engaged, and never shows the "unknown" warning.
      '';
    };
    pollIntervalSec = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Seconds between security probe polls while locked.";
    };
    showDevices = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show "Camera in use" / "Microphone in use" rows on the lock. This is a
        SEPARATE signal from screencastPoll: a browser sharing one of its own
        tabs produces no detectable screen capture at all, so these rows are
        often the only trace such a session leaves. They do NOT mean the screen
        is being shared.
      '';
    };
    showUptime = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show system uptime on the lock.";
    };
    showLastUnlock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show when the session was last unlocked.";
    };
  };

  options.quickshellLock.battery = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show the battery block (percent, time remaining, charge rate) at the
        top-left of the lock, above the security column. Has no effect on a
        machine with no laptop battery -- the block self-hides there.
      '';
    };
    lowPercent = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = ''
        Charge percentage at or below which the battery block tints red. Only
        while DISCHARGING: on AC at the same percentage is not an alarm, it is
        a machine that was just plugged in.
      '';
    };
  };

  config = {
    home.packages = [ lockEscape ];

    # Config seam the QML LockConfig FileView reads. Outside ~/.config/quickshell
    # (the repo symlink) so it never dirties the repo -- mirrors quickshell-idle.
    xdg.configFile."quickshell-lock/config.json".text = builtins.toJSON {
      failOpenOnCrash = cfg.failOpenOnCrash;
      fallbackImage = "${config.home.homeDirectory}/.local/share/lockscreen.png";
      watermark = {
        inherit (cfg.watermark) enable title message color width height;
      };
      backdrop = {
        inherit (cfg.backdrop) mode;
      };
      notifications = {
        inherit (cfg.notifications) enable defaultMode maxCards trustedApps privateApps trustedCategories;
      };
      security = {
        inherit (cfg.security) enable ownerText screencastPoll pollIntervalSec showDevices showUptime showLastUnlock;
      };
      battery = {
        inherit (cfg.battery) enable lowPercent;
      };
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
