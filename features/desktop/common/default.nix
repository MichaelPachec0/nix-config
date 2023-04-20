{ config, pkgs, lib, ... }:
let cfg = config.desktop;
in {
  options = {
    desktop = {
      common = {
        enable = lib.mkEnableOption
          "Enables common desktop apps to install in a graphical environment. Apps work both in Wayland/x11.";
      };
    };
  };
  config = lib.mkIf cfg.common.enable {
    assertions = [{
      # will add all the backends here (wayland/x11)
      assertion = cfg.wayland.laptop || cfg.wayland.desktop;
      message = "Apps here need a X or Wayland backend!";
    }];
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      systemWide = false;
      wireplumber.enable = true;
    };
    environment.systemPackages = with pkgs; [
      # pdf readers, will eventually choose between one or the other
      evince
      okular

      # mail clients
      neomutt

      # video players
      mpv
      vlc

      # telegram
      ## cli
      tg
      ## telegram desktop
      kotatogram-desktop
      ## ncurses telegram + whatapp
      nchat
      ## TODO: find out how this works
      # matterbridge

      # slack
      slack-term
      slack

      # discord
      ## oss discord client
      ripcord
      ## discord in latest electron, also privacy oriented
      webcord
      ## discord in terminal
      discordo

      # view nix tree graphically
      nix-query-tree-viewer
    ];
  };
}
