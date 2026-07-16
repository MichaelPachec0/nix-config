# Home-manager module: a small daemon that keeps matched Hyprland windows
# pinned to a configured position. Some apps (e.g. Windscribe) drift their own
# floating window on resize and Hyprland has no declarative "keep in place"
# rule -- this watches socket2 + polls while a matched window exists and
# re-applies the target position. Daemon logic: ./hypr_window_keeper.py
# (pure helpers covered by ./hypr_window_keeper_test.py).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hyprWindowKeeper;

  # Generated from the `rules` option and read by the daemon at startup.
  configJson =
    pkgs.writeText "hypr-window-keeper.json"
    (builtins.toJSON {rules = cfg.rules;});

  # runtimeInputs puts python3 + hyprctl on PATH; the daemon shells out to
  # `hyprctl` for clients/monitors/dispatch.
  hyprIpc = import ./hypr-ipc-py.nix {inherit pkgs;};

  daemon = pkgs.writeShellApplication {
    name = "hypr-window-keeper";
    runtimeInputs = [pkgs.python3 pkgs.latest.hyprland];
    text = ''
      export PYTHONPATH=${hyprIpc}''${PYTHONPATH:+:$PYTHONPATH}
      exec python3 ${./hypr_window_keeper.py} ${configJson} "$@"
    '';
  };
in {
  options.services.hyprWindowKeeper = {
    enable = lib.mkEnableOption "the Hyprland window position keeper daemon";

    rules = lib.mkOption {
      default = [];
      description = "Windows to keep pinned to a position.";
      type = lib.types.listOf (lib.types.submodule {
        options = {
          match = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            example = {title = "^Windscribe$";};
            description = ''
              Match criteria: any of class / title / initialClass / initialTitle
              mapped to a regex. ALL listed keys must match (re.search).
            '';
          };
          position = lib.mkOption {
            # "center" | { x; y; } | { anchor; margin; } -- validated by the daemon.
            type = lib.types.either lib.types.str lib.types.attrs;
            example = "center";
            description = ''
              Where to pin the window:
                "center"                            centered on its monitor (respects reserved bars)
                { x = <int>; y = <int>; }           fixed, monitor-relative px
                { anchor = "<name>"; margin = N; }  anchored; name is one of
                    center / top / bottom / left / right /
                    top-left / top-right / bottom-left / bottom-right
            '';
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [daemon];

    # Tied to the graphical session (Hyprland is not systemd-managed here, but
    # graphical-session.target is still reached; the daemon self-discovers the
    # Hyprland instance socket, so unit env need not carry the signature).
    systemd.user.services.hypr-window-keeper = {
      Unit = {
        Description = "Keep matched Hyprland windows pinned to a configured position";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Install.WantedBy = ["graphical-session.target"];
      Service = {
        ExecStart = "${daemon}/bin/hypr-window-keeper";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
