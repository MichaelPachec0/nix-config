{ config, pkgs, lib, inputs, ... }:
let cfg = config.desktop;
in {
  options = {
    desktop = {
      wayland = {
        laptop = lib.mkEnableOption "Graphical configuration for laptop";
        desktop = lib.mkEnableOption "Graphical configuration for desktop";
      };
    };
  };
  imports = [ ];
  config = lib.mkIf cfg.laptop || cfg.desktop {
    nix = {
      binaryCachePublicKeys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
      binaryCaches = [ "https://nixpkgs-wayland.cachix.org" ];
    };
    nixpkgs.overlays = [ inputs.nixpkgs-wayland.overlay ];
    environment.systemPackages = with pkgs; [
      # mpv as wallpaper 
      # info: https://github.com/GhostNaN/mpvpaper
      mpvpaper
      cliphist
      eww-wayland
      # auto brightness adjustement
      # more info: https://github.com/maximbaz/wluma
      wluna
      # drm devices utility
      drm_info
      # rdp client for wayland
      freerdp3
      # render glsl shaders as wallpaper
      glpaper
      # grab from wayland compositor
      grim
      # image viewer
      imv
      # auto configure displays
      kanshi
      # notification daemon
      mako
      # might change to this notification deamon
      # info: https://gitlab.com/snakedye/salut
      # salut
      # screenshot ulity (might switch to this)
      # info: https://git.sr.ht/~whynothugo/shotman
      # shotman
      # region selection for wayland
      slurp
      # wallpaper tool more info look at swaybg(1)
      swaybg
      # idle deamon info: https://github.com/swaywm/swayidle/blob/master/swayidle.1.scd
      swayidle
      # vanilla locker
      # swaylock
      # info: https://github.com/mortie/swaylock-effects
      swaylock-effects
      # fancy wallpaper manager
      # info: https://github.com/Horus645/swww
      swww
      # multiuse prompter, supports pinentry (accessed as pinentry-wayprompt),
      #   himitsu (himitsu-wayprompt) and generic prompt (wayprompt-cli)
      wayprompt
      # event viewer
      wev
      # screen recording
      wf-recorder
      # clipboard
      wl-clipboard
      # contrast/brightness/gamma adjuster (using a bar like waybar)
      wl-gammarelay-rs
      # monitor config creator
      wlay
      # app launcher
      wldash
      # logout menu
      wlogout
      # day/night gamma adjuster
      wlsunset
      # vnc client
      wlvncc
      # main launcher
      wofi
      # shows keys pressed
      wshowkeys
      # wayland alternative for xdotool
      wtype
      ## wayland pip video player (not part of the nix community wayland repo) but added here for wayland only config
      qt-video-wlr
    ];

  };

}
