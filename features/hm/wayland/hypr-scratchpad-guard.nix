# Home-manager module: the resident scratchpad daemon. It keeps the Hyprland
# scratchpad (special:magic) float-only AND serves the scratchpad-cycle keybinds:
# it watches socket2 (floats a tiled window moved into the pad) and reads a
# command FIFO (cycle/send/reset/pull/toggle-float/evict) that the keybinds
# write to, running every action IN-PROCESS via scratchpad_cycle.run_command --
# so a keypress or event no longer spawns a fresh python. Daemon logic:
# ./hypr_scratchpad_guard.py (pure classify + run_line parsing covered by
# ./hypr_scratchpad_guard_test.py); it imports scratchpad_cycle + hypr_ipc,
# co-located on PYTHONPATH via ./hypr-scratchpad-py.nix. Pairs with the
# float-forcing send/pull binds and the FIFO-writing wrapper in hyprland.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hyprScratchpadGuard;

  hyprPy = import ./hypr-scratchpad-py.nix {inherit pkgs;};

  # runtimeInputs puts python3 + notify-send on PATH; the daemon reads the event
  # socket and the command FIFO and talks to Hyprland's request socket directly.
  # PYTHONPATH carries hypr_ipc + scratchpad_cycle (imported in-process), no spawn.
  daemon = pkgs.writeShellApplication {
    name = "hypr-scratchpad-guard";
    runtimeInputs = [pkgs.python3 pkgs.libnotify];
    text = ''
      export PYTHONPATH=${hyprPy}''${PYTHONPATH:+:$PYTHONPATH}
      exec python3 ${./hypr_scratchpad_guard.py} "$@"
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
