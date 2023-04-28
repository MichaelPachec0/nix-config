{ inputs, pkgs, config, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
  config = {
    services.swayidle = let
      swaylockSettings =
        " --screenshots  --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --line-color 00000000 --inside-color 00000088 --separator-color 00000000 --grace 2 --fade-in 0.2 -fF";
      lockScreen =
        "${config.programs.swaylock.package}/bin/swaylock ${swaylockSettings}";
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
          resumeCommand = "${hyprctl} dispatch dpms on";
        }
      ];
      systemdTarget = "hyprland-session.target";
    };
  };
}

