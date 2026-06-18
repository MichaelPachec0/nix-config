{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cfg = config.desktop;
  # nwg-displays = inputs.nwg-displays-pkgs.packages.${pkgs.system}.default;
  rust-bin = pkgs.rust-bin.stable."1.87.0".default;
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rust-bin;
    rustc = rust-bin;
  };
  # swayfx = pkgs.nw.swayfx.overrideAttrs (old: {
  #       src = prev.fetchFromGitHub {
  #         owner = "WillPower3309";
  #         repo = "swayfx";
  #         rev = "1710f7ddffbd994722f679fba8674c1919588b78";
  #         # tag = version;
  #         hash = "sha256-gdab7zkjp/S7YVCP1t/OfOdUXZRwNvNSuRFGWEJScF8=";
  #       };
  # });
in {
  options = {
    desktop = {
      wayland = {
        laptop = lib.mkEnableOption "Graphical configuration for laptop";
        desktop = lib.mkEnableOption "Graphical configuration for desktop";
      };
    };
  };
  disabledModules = [
    # "services/system/systemd-lock-handler.nix"
  ];
  imports = [
    # NOTE: this was already merged
    # ../../../../overlays/modules/systemd-lock-handler
  ];

  config = lib.mkIf (cfg.wayland.laptop || cfg.wayland.desktop) {
    nixpkgs.overlays = [
      # (final: prev: let
      #   # TODO: might be better to shadow waybar-hyprland than the parent package.
      #   # TODO #2: see if i can create patch that will accept both sway
      #   # and hyprland commands.
      #   waybarOvr = {isHyprland ? false}: (old: let
      #     date = "01-08-2023";
      #     cava = prev.fetchFromGitHub {
      #       owner = "LukashonakV";
      #       repo = "cava";
      #       # rev = "0.8.5";
      #       rev = "ec4037502beff4dffc798c3a344dad0883a5a451";
      #       sha256 = "06l0dsx4g4s7jmv59fwiinkc2nwla6j581nbsys7agkwp2ldzxbg";
      #     };
      #     rev = "9207fff627059b922fb790e30d68fea23f76146e";
      #     sha256 = "09f4fsmwh6c3zzywwk738dyb6m1lqr4vn06q8vc58ymmx5i8h7gw";
      #     shortRev = builtins.substring 0 7 "${rev}";
      #     pversion = "0.9.22-pre";
      #   in {
      #     pname =
      #       if isHyprland
      #       then "${old.pname}-hyprland"
      #       else old.pname;
      #     withMediaPlayer = true;
      #
      #     version = "${pversion}+date=${date}_${shortRev}";
      #
      #     nativeBuildInputs =
      #       (old.nativeBuildInputs or [])
      #       ++ (with pkgs; [cmake]);
      #
      #     propagatedBuildInputs =
      #       (old.propagatedBuildInputs or [])
      #       ++ (with pkgs; [
      #         iniparser
      #         fftw
      #         ncurses
      #         alsa-lib
      #         libpulseaudio
      #         portaudio
      #         pipewire
      #         SDL2
      #       ]);
      #     src = prev.fetchFromGitHub {
      #       inherit rev sha256;
      #       owner = "Alexays";
      #       repo = "Waybar";
      #     };
      #     mesonFlags =
      #       (old.mesonFlags or [])
      #       ++ (lib.optionals isHyprland ["-Dexperimental=true"]);
      #     postUnpack = ''
      #       rm -rf source/subprojects/cava.wrap
      #       ln -s ${cava} source/subprojects/cava
      #     '';
      #   });
      #   waybar = prev.waybar.overrideAttrs waybarOvr;
      # in {
      #   # inherit waybar;
      # })
      # (final: prev: {
      #   gitoxide = prev.gitoxide.overrideAttrs (old: rec {
      #     cargoDeps = old.cargoDeps.overrideAttrs (_: {
      #       inherit (old) src;
      # outputHash = lib.fakeHash;
      #       outputHash = "sha256-WZctsAxGojrGufF8CwUiw1xWzn9qVZUphDE3KmGTG4=";
      #     });
      #   });
      # })
    ];
    services.systemd-lock-handler = {
      enable = true;
      # package = pkgs.systemd-lock-handler.overrideAttrs (old: rec {
      #   version = "2.4.2";
      #   src = pkgs.fetchFromSourcehut {
      #     owner = "~whynothugo";
      #     repo = "systemd-lock-handler";
      #     rev = "v${version}";
      #     hash = "sha256-sTVAabwWtyvHuDp/+8FKNbfej1x/egoa9z1jLIMJuBg=";
      #   };
      #   vendorHash = "";
      # });
    };
    programs.uwsm = {
      enable = true;
      waylandCompositors = {
        #   hyprland = {
        #   prettyName = "Hyprland";
        #   comment = "Hyprland compositor managed by UWSM";
        #   binPath = "/run/current-system/sw/bin/Hyprland";
        # };
        sway = {
          prettyName = "Sway";
          comment = "Sway compositor managed by UWSM";
          binPath = "/run/current-system/sw/bin/sway";
        };
      };
    };
    programs.hyprland = {
      enable = true;
      package = pkgs.latest.hyprland;
      # package = hyprland.hyprland.override {
      #   wlroots = hyprland.wlroots-hyprland.override {
      #     inherit (pkgs.nw) wlroots;
      #   };
      # };
      xwayland = {
        enable = true;
      };
      withUWSM = true;
    };
    xdg = {
      mime = let
        # NOTE: this is so that links are opened in the browser.
        # For some reason the the associations are not being registered.
        # TODO: (low prio) mimeapps already had some entries, include these as well:
        #
        # [Default Applications]
        #
        # [Added Associations]
        # x-scheme-handler/tg=userapp-Kotatogram Desktop-KVRF21.desktop;userapp-Telegram Desktop-ENXU31.desktop;
        # TODO: (high prio) (research) find out why the registration does not
        # happen, and if this only applies to firefx.
        # NOTE: This had to do with some env variables not being set correctly.
        # Fixed in wm config.
        browser = [
          # firefox-developer-edition.desktop
          "firefox-developer-edition.desktop"
          # it is assumed this is ordered, which means that developer edition is queried first.
          "firefox-devedition.desktop"
          "firefox.desktop" # assume regular firefox provides this
        ];
        av = [
          "mpv.desktop"
          "vlc.desktop"
        ];
        discord = ["legcord.desktop"];
        associations = {
          # "inode/directory" = ["org.kde.dolphin.desktop"];
          # WARN: this might change, dont know what to do about this.
          "x-scheme-handler/tg" = ["userapp-Telegram Desktop-ENXU31.desktop" "org.telegram.desktop.desktop"];
          "x-scheme-handler/notion" = "notion-app-enhanced.desktop";

          "text/html" = browser;
          "x-scheme-handler/http" = browser;
          "x-scheme-handler/https" = browser;
          "x-scheme-handler/ftp" = browser;
          "x-scheme-handler/chrome" = browser;
          "x-scheme-handler/about" = browser;
          "x-scheme-handler/unknown" = browser;
          "application/x-extension-htm" = browser;
          "application/x-extension-html" = browser;
          "application/x-extension-shtml" = browser;
          "application/xhtml+xml" = browser;
          "application/x-extension-xhtml" = browser;
          "application/x-extension-xht" = browser;
          "application/json" = browser; # .json
          "application/pdf" = browser; # .pdf
          "image/*" = "feh.desktop";
          "audio/*" = av;
          "video/*" = av;
          "x-scheme-handler/discord" = discord;
        };
      in {
        enable = true;
        defaultApplications =
          {
          }
          // associations;
        addedAssociations =
          {
          }
          // associations;
      };
      portal = {
        enable = true;
        xdgOpenUsePortal = true;
        wlr = {
          enable = true;
          settings.screencast = {
            # to make sure that notifications do not show up when screensharing
            #   r: https://github.com/ErikReider/SwayNotificationCenter?tab=readme-ov-file#notification-inhibition
            exec_before = ''which swaync-client && swaync-client --inhibitor-add "xdg-desktop-portal-hyprland" || true'';
            exec_after = ''which swaync-client && swaync-client --inhibitor-remove "xdg-desktop-portal-hyprland" || true'';
          };
        };
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
          # xdg-desktop-portal-wlr
          # xdg-desktop-portal-hyprland
        ];
        config = {
          sway = {
            # ... except for the ScreenCast, Screenshot and Secret
            "org.freedesktop.impl.portal.ScreenCast" = ["wlr"];
            "org.freedesktop.impl.portal.Screenshot" = ["wlr"];
            # ignore inhibit bc gtk portal always returns as success,
            # despite sway/the wlr portal not having an implementation,
            # stopping firefox from using wayland idle-inhibit
            "org.freedesktop.impl.portal.Inhibit" = ["none"];
            # make sure that gnome-keyring is enabled
            "org.freedesktop.impl.portal.Secret" = [
              "gnome-keyring"
            ];
            "org.freedesktop.impl.portal.GlobalShortcuts" = ["none"];
          };
          hyprland.default = ["hyprland"];
          common = {
            default = [
              "gtk"
            ];
          };
          pantheon = {
            default = [
              "pantheon"
              "gtk"
            ];
            "org.freedesktop.impl.portal.Secret" = [
              "gnome-keyring"
            ];
          };
          x-cinnamon = {
            default = [
              "xapp"
              "gtk"
            ];
          };
        };
      };
    };
    programs.sway = {
      enable = true;
      # package = pkgs.latest.sway;
      # package = pkgs.nw.sway-beta;
      # package = pkgs.master.sway;
      package = pkgs.sway;

      # prev
      # package = pkgs.unstable.sway;
      wrapperFeatures.gtk = true;
    };
    services.displayManager.sessionPackages = [
      pkgs.nw.swayfx
    ];
    # environment.systemPackages = [pkgs.nw.swayfx];

    environment.variables = {
      # NOTE: use the new fancy wayland backend.
      # WLR_BACKEND = "vulkan";
      # WLR_RENDERER = "vulkan";
      # HACK: This is set to workaround displays that do not enable properly.
      # https://github.com/swaywm/wlroots/issues/1877
      # WLR_DRM_NO_MODIFIERS = "1";
      NIXOS_OZONE_WL = "1";
    };

    # Needed for sway/hyprland usage HM as per:
    # https://nixos.wiki/wiki/Sway#Using_Home_Manager
    security.polkit.enable = true;
    # secrets storage (ssh keys... ect)
    services.gnome.gnome-keyring.enable = true;
    services.colord.enable = true;

    environment.systemPackages = with pkgs; [
      pkgs.nw.swayfx
      # TODO: make icc profile declarative
      colord-gtk
      master.beeper
      # nw.swayfx
      xorg.xprop # so HiDPI can be set correctly in xwayland
      # mpv as wallpaper
      # info: https://github.com/GhostNaN/mpvpaper
      mpvpaper
      cliphist
      # 2025-11-05: eww-wayland to eww
      eww
      # TODO: CHECK IF THIS IS FIXED: ERR in tests with i3ipc
      stable.nwg-displays
      # recommended by hyprland dev for auth-agent
      kdePackages.polkit-kde-agent-1
      # secrets viewer
      # gnome.seahorse
      seahorse
      # file browser (might change this)
      # cinnamon.nemo
      nemo
      # auto brightness adjustement
      # more info: https://github.com/maximbaz/wluma
      wluma
      # master.waybar
      # drm devices utility
      nw.drm_info
      # rdp client for wayland
      nw.freerdp3
      # render glsl shaders as wallpaper
      # nw.glpaper
      # grab from wayland compositor
      nw.grim
      # image viewer
      nw.imv
      # auto configure displays
      nw.kanshi
      # notification daemon
      #nw.mako
      # dunst
      # might change to this notification deamon
      # info: https://gitlab.com/snakedye/salut
      # salut
      # screenshot ulity (might switch to this)
      # info: https://git.sr.ht/~whynothugo/shotman
      # shotman
      # region selection for wayland
      nw.slurp
      # wallpaper tool more info look at swaybg(1)
      nw.swaybg
      # idle deamon info:
      # https://github.com/swaywm/swayidle/blob/master/swayidle.1.scd
      # swayidle
      # (pkgs.swayidle.override {systemdSupport = false;})
      nw.swayidle-test
      # vanilla locker
      swaylock
      # info: https://github.com/mortie/swaylock-effects
      # swaylock-effects
      #swaylock-effects-pr
      # fancy wallpaper manager
      # info: https://github.com/Horus645/swww
      # (nw.swww.override {inherit rustPlatform;})
      # nw.swww
      # swww
      # multiuse prompter, supports pinentry (accessed as pinentry-wayprompt),
      #   himitsu (himitsu-wayprompt) and generic prompt (wayprompt-cli)
      # nw.wayprompt
      # event viewer
      nw.wev
      # screen recording
      nw.wf-recorder
      # clipboard
      nw.wl-clipboard
      # contrast/brightness/gamma adjuster (using a bar like waybar)
      nw.wl-gammarelay-rs
      # monitor config creator
      nw.wlay
      # app launcher
      wldash
      # logout menu
      nw.wlogout
      # day/night gamma adjuster
      nw.wlsunset
      # vnc client
      stable.wlvncc
      # main launcher
      nw.wofi
      # shows keys pressed
      nw.wshowkeys
      # wayland alternative for xdotool
      nw.wtype
      # randr tool for wayland
      nw.wlr-randr
      # network manager for dmenu
      glib
      xdg-utils
      # opens desktop files in the terminal, with a more ergonomic ux
      dex
      # applications that deal with gtk3, including opening desktop files (gtk-launch)
      gtk3
      # gui wallpaper
      waypaper
      # independent (no depencies on wayland or x11) keyboard emulation tool.
      ydotool
      # TODO: move to its own file
      # jadx BORKED as of 2/20/25
      fermyon-spin
      xorg.xeyes
      localsend
      tun2socks
      shadowsocks-rust
      remmina
      ghidra
      # TODO: cmake issues with stable
      # pkgs.master.imhex
      ncspot
      # ((pkgs.ncspot.override {withCover = true;}).overrideAttrs
      #   (old: {
      #     # cargoBuildFlags = ["--features=cover"];
      #   }))

      #NOTE: this is from hm/wayland
      # hyprland.default
      material-icons
      charles
      go-mtpfs
      swayest-workstyle
      swaysome
      # unmaintained, need to use crosspipe
      # helvum
      crosspipe
      coppwr
      kitty
      # latest.waybar
      waybar

      adwaita-qt
      adwaita-qt6

      # 2026-06-18: change was made to remove the top level libsForQt5
      qt5.qtbase
      qadwaitadecorations
      qadwaitadecorations-qt6
      # 2026-06-18: change was made to remove the top level libsForQt5
      libsForQt5.qtstyleplugins
      qt6Packages.qt6gtk2
      activate-linux
      obs-studio
      # nw.zen-browser
      # thunderbird
      slack
      slack-term
      neovide
      joshuto
    ];
    # systemd.user.units."dunst" = {wantedBy = ["hyprland-session.target"];};
    systemd.services = {
      seatd = {
        enable = false;
        description = "Seat management daemon";
        script = "${lib.getExe pkgs.seatd} -g wheel";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
        };
        wantedBy = ["multi-user.target"];
      };
    };
    virtualisation.waydroid.enable = true;
    services.flatpak.enable = true;
    # so sway gets covers in mpris
    services.gvfs.enable = true;
  };
}
