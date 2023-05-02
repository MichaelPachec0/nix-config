{ inputs, pkgs, config, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
  config = {
    xdg.configFile."swaylock/config".source = let
      config = pkgs.writeText "swaylockConfig" ''
        screenshots
        clock
        indicator
        indicator-radius=100
        indicator-thickness=7
        effect-blur=7x5
        effect-vignette=0.5:0.5
        ring-color=bb00cc
        key-hl-color=880033
        line-color=00000000
        inside-color=00000088
        seperator-color=00000000
        grace=2
        fade-in=0.2
        daemonize
        show-failed-attempts
      '';
    in config;
    services.swayidle = let
      # swaylockSettings =
      # " --screenshots  --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --line-color 00000000 --inside-color 00000088 --separator-color 00000000 --grace 2 --fade-in 0.2 -fF";
      lockScreen =
        #"${pkgs.swaylock-effects-pr}/bin/swaylock ${swaylockSettings}";
        "${pkgs.swaylock-effects-pr}/bin/swaylock";
      #"${pkgs.unstable.swaylock-effects}/bin/swaylock ${swaylockSettings}";
      hyprctl = "${config.wayland.windowManager.hyprland.package}/bin/hyprctl";
    in {
      enable = true;
      package = pkgs.unstable.swayidle;
      events = [
        {
          event = "before-sleep";
          command = "${lockScreen}";
        }
        {
          event = "lock";
          command = "${lockScreen}";
        }
      ];
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

