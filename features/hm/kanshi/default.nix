{ inputs, pkgs, config, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
  imports = [ ];
  options = { };
  config = {
    services = {
      kanshi = let
        # TODO: include sway and newm commands as well
        hyprctl =
          "${config.wayland.windowManager.hyprland.package}/bin/hyprctl";
      in {
        enable = true;
        package = nw.kanshi;
        systemdTarget = "graphical-session.target";
        profiles = {
          default-setup = {
            outputs = [{
              # 4k display from xps 9560
              criteria = "eDP-1";
              scale = 1.5;
              status = "enable";
              position = "0,0";
              mode = "3840x2160@59.99Hz";
            }];
          };
          mobile-with-monitor = {
            # This does the 90 deg rotation since kanshi cannot do it on its own
            exec = [ "${hyprctl} keyword monitor DP-1, transform,1" ];
            outputs = [
              {
                # 4k display from xps 9560
                criteria = "eDP-1";
                scale = 1.5;
                status = "enable";
                position = "1080,0";
                mode = "3840x2160@59.99Hz";
              }
              {
                # Would like to name this monitor but sometimes this monitor likes to call 
                # itself "(null) (null)" which is extremely annoying to diagnose, 
                # assume that all mobile monitors that are connected to the usbc port are 1080p@60Hz
                criteria = "DP-1";
                scale = 1.0;
                status = "enable";
                position = "0,0";
                mode = "1920x1080@60Hz";
                transform = "flipped-90";

              }
            ];
          };
          home-docked = {
            # one big blob to ensure there is enough time for the asus monitor to wake up
            # TODO: Do not execute anything here, need to find out why specifically on this setup laptop display freezes. Might need add a sleep
            # after every command.
            exec = [
              #"sleep 30; hyprctl dispatch moveworkspacetomonitor 1 eDP-1; sleep 1; hyprctl dispatch moveworkspacetomonitor 2 HDMI-A-1; sleep 1; hyprctl dispatch moveworkspacetomonitor 3 DP-2; sleep 1; hyprctl dispatch moveworkspacetomonitor 4 eDP-1; sleep 1; hyprctl dispatch moveworkspacetomonitor 5 DP-2; sleep 1; hyprctl dispatch moveworkspacetomonitor 6 HDMI-A-1"
            ];
            outputs = [
              {
                criteria = "eDP-1";
                scale = 1.5;
                status = "enable";
                position = "0,0";
                mode = "3840x2160@59.99Hz";
              }
              {
                criteria = "ASUSTek COMPUTER INC VG279 K5LMQS018158";
                scale = 1.0;
                status = "enable";
                position = "2560,0";
                mode = "1920x1080@120Hz";
              }
              {
                criteria = "Acer Technologies Acer ET241Y T9AAA0024209";
                scale = 1.0;
                status = "enable";
                position = "4480,0";
                mode = "1920x1080@60Hz";
              }
            ];
          };
          home-docked-asus = {
            outputs = [
              {
                criteria = "eDP-1";
                scale = 1.5;
                status = "enable";
                position = "0,0";
                mode = "3840x2160@59.99Hz";
              }
              {
                criteria = "ASUSTek COMPUTER INC VG279 K5LMQS018158";
                scale = 1.0;
                status = "enable";
                position = "2560,0";
                mode = "1920x1080@120Hz";
              }
            ];
          };

          home-docked-acer = {
            outputs = [
              {
                criteria = "eDP-1";
                scale = 1.5;
                status = "enable";
                position = "0,0";
                mode = "3840x2160@59.99Hz";
              }
              {
                criteria = "Acer Technologies Acer ET241Y T9AAA0024209";
                scale = 1.0;
                status = "enable";
                position = "2560,0";
                mode = "1920x1080@60Hz";
              }
            ];
          };
        };
      };
    };
  };
}
