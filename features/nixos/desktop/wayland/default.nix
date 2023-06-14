{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.desktop;
  nwg-displays = inputs.nwg-displays-pkgs.packages.${pkgs.system}.default;
in {
  options = {
    desktop = {
      wayland = {
        laptop = lib.mkEnableOption "Graphical configuration for laptop";
        desktop = lib.mkEnableOption "Graphical configuration for desktop";
      };
    };
  };
  imports = [
    inputs.hyprland.nixosModules.default
    ../../../../overlays/modules/systemd-lock-handler
  ];

  config = let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
  in lib.mkIf (cfg.wayland.laptop || cfg.wayland.desktop) {
    nix = {
      binaryCachePublicKeys = [
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="

      ];
      binaryCaches =
        [ "https://nixpkgs-wayland.cachix.org" "https://hyprland.cachix.org" ];
    };
    nixpkgs.overlays = [
      #(final: prev: { waybar = pkgs.unstable.waybar.override { withMediaPlayer = true;}; })
      # waybar-hyprland will take on these options.
      # TODO: might be better to shadow waybar-hyprland than the parent package.
      # TODO #2: see if i can create patch that will accept both sway and hyprland commands.
      (final: prev: {
        waybar = pkgs.unstable.waybar.overrideAttrs (old:
          let
            date = "5-30-2023";
            cava = prev.fetchFromGitHub {
              owner = "LukashonakV";
              repo = "cava";
              rev = "0.8.4";
              sha256 = "0hi5cam7gfyziplnlf1mfq8j263ggqxib8rl79bmz29b4789razb";
            };
            rev = "47193a3d2f81a8ce7177449f92e927db74d873b0";
            shortRev = builtins.substring 0 7 "${rev}";
            version = "0.9.18";
          in {
            withMediaPlayer = true;

            version = "${version}+date=${date}_${shortRev}";

            nativeBuildInputs = (old.nativeBuildInputs or [ ])
              ++ (with pkgs; [ cmake ]);

            propagatedBuildInputs = (old.propagatedBuildInputs or [ ])
              ++ (with pkgs; [
                iniparser
                fftw
                ncurses
                alsa-lib
                libpulseaudio
                portaudio
                pipewire
                SDL2
              ]);
            src = prev.fetchFromGitHub {
              inherit rev;
              owner = "Alexays";
              repo = "Waybar";
              sha256 = "bnaYNa1jb7kZ1mtMzeOQqz4tmBG1w5YXlQWoop1Q0Yc=";
            };
            postUnpack = ''
              rm -rf source/subprojects/cava.wrap
              ln -s ${cava} source/subprojects/cava
            '';
          });
      })

    ];
    services.systemd-lock-handler = {
      enable = true;
    };

    programs.hyprland = {
      enable = true;
      xwayland = {
        enable = true;
        hidpi = true;
      };
    };
    # This is already set in regreet, but for the purposes of being explicit, define it here as well
    programs.sway = { enable = true; };

    # secrets storage (ssh keys... ect)
    services.gnome.gnome-keyring.enable = true;

    environment.systemPackages = with pkgs; [
      # mpv as wallpaper 
      # info: https://github.com/GhostNaN/mpvpaper
      mpvpaper
      cliphist
      eww-wayland
      nwg-displays
      # recommended by hyprland dev for auth-agent
      polkit-kde-agent
      # secrets viewer
      gnome.seahorse
      # file browser (might change this)
      cinnamon.nemo
      # auto brightness adjustement
      # more info: https://github.com/maximbaz/wluma
      wluma
      # waybar with hyprland patches
      waybar-hyprland
      # drm devices utility
      nw.drm_info
      # rdp client for wayland
      nw.freerdp3
      # render glsl shaders as wallpaper
      nw.glpaper
      # grab from wayland compositor
      nw.grim
      # image viewer
      nw.imv
      # auto configure displays
      nw.kanshi
      # notification daemon
      #nw.mako
      nw.dunst
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
      # idle deamon info: https://github.com/swaywm/swayidle/blob/master/swayidle.1.scd
      unstable.swayidle
      # vanilla locker
      # swaylock
      # info: https://github.com/mortie/swaylock-effects
      # unstable.swaylock-effects
      swaylock-effects-pr
      # fancy wallpaper manager
      # info: https://github.com/Horus645/swww
      nw.swww
      # multiuse prompter, supports pinentry (accessed as pinentry-wayprompt),
      #   himitsu (himitsu-wayprompt) and generic prompt (wayprompt-cli)
      nw.wayprompt
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
      nw.wldash
      # logout menu
      nw.wlogout
      # day/night gamma adjuster
      nw.wlsunset
      # vnc client
      nw.wlvncc
      # main launcher
      nw.wofi
      # shows keys pressed
      nw.wshowkeys
      # wayland alternative for xdotool
      nw.wtype
      # randr tool for wayland
      nw.wlr-randr
      ## wayland pip video player (not part of the nix community wayland repo) but added here for wayland only config
      qt-video-wlr
      # automation?
      ydotool
    ];
    systemd.user.units."dunst" = { wantedBy = [ "graphical-session.target" ]; };
  };

}
