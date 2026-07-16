# Home-manager module: a small daemon that keeps the Hyprland scratchpad
# (special:magic) float-only. It watches socket2 and, via the scratchpad-cycle
# subcommands, (a) evicts a pad member whose floating attribute is turned off
# and (b) floats a tiled window that is moved into the pad. Daemon logic:
# ./hypr_scratchpad_guard.py (pure classify covered by
# ./hypr_scratchpad_guard_test.py); shared socket2 glue from ./hypr_ipc.py
# (co-located on PYTHONPATH via ./hypr-ipc-py.nix). The daemon shells out to
# ./scratchpad_cycle.py (passed by store path) so all pad state lives in one
# place. Pairs with the float-forcing send/pull binds in hyprland.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hyprScratchpadGuard;

  hyprIpc = import ./hypr-ipc-py.nix {inherit pkgs;};

  # runtimeInputs puts python3 + hyprctl + notify-send on PATH; the daemon and
  # the scratchpad-cycle subcommands it invokes read the event socket and shell
  # out to hyprctl. PYTHONPATH carries the shared hypr_ipc module.
  daemon = pkgs.writeShellApplication {
    name = "hypr-scratchpad-guard";
    runtimeInputs = [pkgs.python3 pkgs.latest.hyprland pkgs.libnotify];
    text = ''
      export PYTHONPATH=${hyprIpc}''${PYTHONPATH:+:$PYTHONPATH}
      exec python3 ${./hypr_scratchpad_guard.py} ${./scratchpad_cycle.py} "$@"
    '';
  };
in {
  options.services.hyprScratchpadGuard = {
    enable = lib.mkEnableOption "the Hyprland scratchpad float-only guard daemon";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [daemon];

    # Tied to the graphical session (Hyprland is not systemd-managed here, but
    # graphical-session.target is still reached; the daemon self-discovers the
    # Hyprland instance socket, so unit env need not carry the signature).
    systemd.user.services.hypr-scratchpad-guard = {
      Unit = {
        Description = "Keep the Hyprland scratchpad (special:magic) float-only";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Install.WantedBy = ["graphical-session.target"];
      Service = {
        ExecStart = "${daemon}/bin/hypr-scratchpad-guard";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
