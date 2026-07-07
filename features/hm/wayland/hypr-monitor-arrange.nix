# Home-manager module: a small daemon that re-arranges Hyprland layer surfaces
# after a monitor is removed. On unplug, Hyprland core migrates the removed
# monitor's layer-shell surfaces (wallpaper, bar, notification popups) to a
# surviving monitor but skips arrangeLayersForMonitor, leaving them stranded at
# the dead monitor's origin (off-screen). This watches socket2 and runs
# `hyprctl reload` (which re-runs the arrange pass) on `monitorremoved`.
# Daemon logic: ./hypr_monitor_arrange.py (pure helpers covered by
# ./hypr_monitor_arrange_test.py). Workaround for a Hyprland-core bug; hy3 is
# not involved (it lays out tiled windows, not layer surfaces).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hyprMonitorArrange;

  # runtimeInputs puts python3 + hyprctl on PATH; the daemon shells out to
  # `hyprctl reload` and reads the Hyprland event socket.
  daemon = pkgs.writeShellApplication {
    name = "hypr-monitor-arrange";
    runtimeInputs = [pkgs.python3 pkgs.latest.hyprland];
    text = ''exec python3 ${./hypr_monitor_arrange.py} "$@"'';
  };
in {
  options.services.hyprMonitorArrange = {
    enable = lib.mkEnableOption "the Hyprland monitor-removed layer re-arrange daemon";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [daemon];

    # Tied to the graphical session (Hyprland is not systemd-managed here, but
    # graphical-session.target is still reached; the daemon self-discovers the
    # Hyprland instance socket, so unit env need not carry the signature).
    systemd.user.services.hypr-monitor-arrange = {
      Unit = {
        Description = "Re-arrange Hyprland layer surfaces after a monitor is removed";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Install.WantedBy = ["graphical-session.target"];
      Service = {
        ExecStart = "${daemon}/bin/hypr-monitor-arrange";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
