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
    programs.firefox = {
      enable = true;
      package = pkgs.firefox-devedition-bin;
    };
    environment.systemPackages = with pkgs;
      [
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
        unstable.nchat
        whatsapp-for-linux
        ## TODO: find out how this works
        # matterbridge

        # slack
        slack-term
        slack

        # discord
        ## oss discord client
        ripcord
        ## discord in latest electron, also privacy oriented
        unstable.webcord
        ## discord in terminal
        unstable.discordo

        # view nix tree graphically
        nix-query-tree-viewer

        # terminal notetaking app
        nb

        #partition management
        gparted

      # view nix tree graphically
      nix-query-tree-viewer
    ];
  };
}
