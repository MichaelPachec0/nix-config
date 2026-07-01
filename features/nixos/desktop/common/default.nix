{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cfg = config.desktop;
in {
  options = {
    desktop = {
      common = {
        enable =
          lib.mkEnableOption
          "Enables common desktop apps to install in a graphical environment. Apps work both in Wayland/x11.";
      };
    };
  };
  imports = [
  ];
  config = lib.mkIf cfg.common.enable {
    assertions = [
      {
        # will add all the backends here (wayland/x11)
        assertion = cfg.wayland.laptop || cfg.wayland.desktop;
        message = "Apps here need a X or Wayland backend!";
      }
    ];
    fonts.fontDir.enable = true;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = true;
      systemWide = false;
      wireplumber = {
        enable = true;
      };
    };
    programs.firefox = {
      enable = true;
      # package = pkgs.firefox;
      package = pkgs.latest.firefox-devedition-bin;
      # package = pkgs.firefox-beta-bin;

      # pkgs.firefox-devedition-bin.overrideAttrs (let
      #   # NOTE: This is for 116.0b8.
      #   url = "https://archive.mozilla.org/pub/devedition/releases/116.0b8/linux-x86_64/en-US/firefox-116.0b8.tar.bz2";
      #   sha256 = "fdde9c378b5b184e8ed81d62eb03dd39bae52496e742ed960fd16eeb299c6662";
      # in
      #   old: rec {
      #     src = builtins.fetchurl {inherit url sha256;};
      #   });
      # nativeMessagingHosts = {
      #   ff2mpv = true;
      # tridactyl = true;
      # };
      nativeMessagingHosts = {
        packages = [pkgs.tridactyl-native];
      };
    };
    nixpkgs.overlays = [];
    environment.systemPackages = with pkgs;
      [
        nmap
        # password
        keepassxc
        # telegram
        # 2025-11-05: tdesktop changed to telegram-desktop
        telegram-desktop
        # the package below still uses openssl 1.1.x, until
        # https://github.com/NixOS/nixpkgs/pull/234359 gets merged, keep commented out.
        #kotatogram-desktop

        # vnc
        wayvnc
        # browsers
        nyxt
        #firefox-esr

        # NOTE: depends on qute
        # qutebrowser

        # pdf readers, will eventually choose between one or the other
        evince
        kdePackages.okular
        zathura

        # mail clients
        neomutt
        # electron-mail
        electron-mail-latest

        # video players
        # WARN: mpv: 2026-06-18: getting errors trying to build
        mpv

        # vlc

        # WARN: mpv: 2026-06-18: getting errors trying to build
        open-in-mpv

        # telegram
        ## cli
        tg
        ## ncurses telegram + whatapp
        nchat

        # 2025-11-05: whatsapp-for-linux has been renamed to wasistlos
        # wasistlos
        karere
        ## TODO: (med prio) (research) find out how this works
        # Bridges between most if not all social networks. Does not need mattermost.
        # matterbridge

        # slack
        slack-term
        # slack

        # discord
        ## oss discord client
        ripcord
        ## discord in latest electron, also privacy oriented
        # NOTE: this should only be temporary
        # WARN: Do not know if this is a problem with my environment (and does not represent of most) or if its a valid issue.
        # this was based on https://github.com/ArmCord/ArmCord/issues/354#issuecomment-1480432789
        (let
          xdg-open-ovr =
            runCommandWith {
              name = "xdg-open-override";
              derivationArgs.nativeBuildInputs = [makeWrapper];
            } ''
              # Wrap xdg-open, unsetting `LD_LIBRARY_PATH` becuase it's used by
              # the `armcord` package to inject libraries at runtime; these conflict
              # with Firefox, etc.
              makeWrapper ${xdg-utils}/bin/xdg-open $out/bin/xdg-open \
                --unset LD_LIBRARY_PATH
            '';
        in
          # master has issues with legcord???
          # master.legcord.overrideAttrs (_: {
          legcord.overrideAttrs (_: {
            postFixup = ''
              # TODO: find a better way of doing this
              wrapProgram $out/bin/legcord \
              --append-flags "--ozone-platform-hint=auto" \
              --prefix PATH : "${xdg-open-ovr}/bin" \
            '';
          }))
        # master.armcord.overrideAttrs (_: {
        #   postFixup = ''
        #     # TODO: find a better way of doing this
        #     wrapProgram $out/bin/armcord \
        #     --append-flags "--ozone-platform-hint=auto" \
        #     --prefix PATH : "${xdg-open-ovr}/bin" \
        #   '';
        # }))
        ## discord in terminal
        discordo

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
        shikane
        # 2025-11-05: tor-browser-bundle-bin to tor-browser
        tor-browser

        scream
        brave
        ungoogled-chromium
        #office
        # libreoffice-qt
        hunspell
        hunspellDicts.en_US-large
        hunspellDicts.es_MX
        notion-app-enhanced

        #onthespot # ENABLE AFTER

        scrcpy
        neomutt
        obsidian
        obsidian-export
        udftools
        pbpctrl
      ]
      ++ lib.optionals config.networking.wireless.iwd.enable [iwgtk]
      ++ lib.optionals config.devMachine.enable [
        # stable.jetbrains.pycharm-professional
        # stable.jetbrains.phpstorm
        # stable.jetbrains.idea-ultimate
        # stable.jetbrains.goland
        # stable.jetbrains.clion
        # stable.jetbrains.webstorm
      ];
    services.syncthing = {
      enable = true;
      openDefaultPorts = true; # Open ports in the firewall for Syncthing. (NOTE: this will not open syncthing gui port)
    };
    systemd = {
      user.services.polkit-gnome-authentication-agent-1 = {
        description = "polkit-gnome-authentication-agent-1";
        wantedBy = ["graphical-session.target"];
        wants = ["graphical-session.target"];
        after = ["graphical-session.target"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
      };
    };
    programs.appimage.binfmt = true;
    services.windscribe.enable = true;
  };
}
