{ inputs, pkgs, config, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
  config = {
    services.swayidle = let
      lockScreen = "${nw.swaylock-effects}/bin/swaylock -fF";
      hyprctl = "${config.wayland.windowManager.hyprland.package}/bin/hyprctl";
    in {
      enable = true;
      package = nw.swayidle;
      events = [{
        event = "before-sleep";
        command = "${lockScreen}";
      }];
      timeouts = [
        {
          timeout = 300;
          command = "${lockScreen}";
        }
        {
          timeout = 800;
          command = "${hyprctl} dispatch dpms off";
          resumeCommand = "{hyprctl} dispatch dpms on";
        }
      ];
      systemdTarget = "hyprland-session.target";
    };
  };
}

