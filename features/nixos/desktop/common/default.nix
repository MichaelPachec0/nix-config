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
    nixpkgs.overlays = [
      (final: prev: {
        wpsoffice = prev.wpsoffice.overrideAttrs (old: rec {
          version = "11.1.0.11698";
          src = prev.fetchurl {
            url =
              "https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/${
                lib.last (lib.splitString "." version)
              }/wps-office_${version}.XA_amd64.deb";
            sha256 = "sha256-spqxQK/xTE8yFPmGbSbrDY1vSxkan2kwAWpCWIExhgs=";
            curlOpts =
              "--resolve wdl1.pcfg.cache.wpscdn.com:443:104.17.187.189";
          };
        });
      })
    ];
    environment.systemPackages = with pkgs;
      [
        nmap
        # password
        keepassxc
        # telegram
        tdesktop
        #kotatogram-desktop

        # vnc
        unstable.wayvnc
        remmina
        # browsers
        nyxt
        #firefox-esr
        qutebrowser
        # pdf readers, will eventually choose between one or the other
        evince
        okular
        zathura

        # mail clients
        neomutt
        electron-mail-latest

        # video players
        mpv
        vlc

        # telegram
        ## cli
        tg
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

        # irc
        weechat
        # newsreader
        newsboat
        # youtube
        yt-dlp
        tartube-yt-dlp
        # brightness control
        brightnessctl
        unstable.shikane
      ] ++ lib.optionals (config.networking.wireless.iwd.enable) [ iwgtk ];
  };
}

