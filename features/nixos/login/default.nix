{ config, lib, pkgs, ... }:
let cfg = config.services.graphicalLogin;
in {
  options = {
    services = {
      graphicalLogin = {
        enable =
          lib.mkEnableOption "Setups greetd and other login configuration.";
        wallpaper = lib.mkOption {
          default = null;
          type = lib.types.nullOr lib.types.path;
          description = lib.mdDoc ''
            path to the wallpaper wanted
          '';
        };
      };
    };
  };
  config = lib.mkIf cfg.enable {
    # use sway as backend compositor, since it displays correctly on HiDPI
    # Do not set anything else, sway on nixos at least already has sane defaults
    # User setup can happen on home-manager for the user
    programs.sway = { enable = true; };
    # use regreet as the greetd DM
    programs.regreet = {
      enable = true;
      # use unstable version of regreet
      package = pkgs.unstable.greetd.regreet;
      # do not set settings here yet
      # settings = {};
    };
    # enable greetd
    services.greetd = {
      enable = true;
      # restart on logout
      restart = true;
      settings = {
        default_session = {
          # use dbus for faster execution
          command = "${pkgs.dbus}/bin/dbus-run-session ${
              lib.getExe pkgs.sway
            } --config /etc/greetd/sway-config";
          # set user explicitly
          user = "greeter";
        };
      };
    };
    # 
    environment.etc."greetd/environment".text = ''
      Hyprland
      sway
      zsh
    '';
    environment.etc."greetd/sway-config".text = ''
      exec "${lib.getExe config.programs.regreet.package}; swaymsg exit"
      include /etc/sway/config.d/*
    '';

  };
}
