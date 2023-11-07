{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [./swayidle.nix];
  config = let
    hyprland = inputs.hyprland.packages.${pkgs.system};
    cfg = config;
  in {
    nixpkgs.overlays = [
      (final: prev: let
        # TODO: might be better to shadow waybar-hyprland than the parent package.
        # TODO #2: see if i can create patch that will accept both sway
        # and hyprland commands.
        waybarOvr = {isHyprland ? false}: (old: let
          date = "01-08-2023";
          cava = prev.fetchFromGitHub {
            owner = "LukashonakV";
            repo = "cava";
            # rev = "0.8.5";
            rev = "ec4037502beff4dffc798c3a344dad0883a5a451";
            sha256 = "06l0dsx4g4s7jmv59fwiinkc2nwla6j581nbsys7agkwp2ldzxbg";
          };
          rev = "9207fff627059b922fb790e30d68fea23f76146e";
          sha256 = "09f4fsmwh6c3zzywwk738dyb6m1lqr4vn06q8vc58ymmx5i8h7gw";
          shortRev = builtins.substring 0 7 "${rev}";
          pversion = "0.9.22-pre";
        in {
          pname =
            if isHyprland
            then "${old.pname}-hyprland"
            else old.pname;
          withMediaPlayer = true;

          version = "${pversion}+date=${date}_${shortRev}";

          nativeBuildInputs =
            (old.nativeBuildInputs or [])
            ++ (with pkgs; [cmake]);

          propagatedBuildInputs =
            (old.propagatedBuildInputs or [])
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
            inherit rev sha256;
            owner = "Alexays";
            repo = "Waybar";
          };
          mesonFlags =
            (old.mesonFlags or [])
            ++ (lib.optionals isHyprland ["-Dexperimental=true"]);
          postUnpack = ''
            rm -rf source/subprojects/cava.wrap
            ln -s ${cava} source/subprojects/cava
          '';
        });
        waybar = prev.waybar.overrideAttrs waybarOvr;
      in {
        inherit waybar;
      })
    ];
    wayland.windowManager.hyprland = {
      enable = true;
      systemdIntegration = true;
      xwayland = {
        enable = true;
        hidpi = true;
      };
    };

    home.pointerCursor = {
      #name = "phinger-cursors";
      #package = pkgs.phinger-cursors;
      name = "Adwaita";
      package = pkgs.gnome3.adwaita-icon-theme;
      size = 24;
      gtk.enable = true;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    gtk = {
      enable = true;
      cursorTheme = {
        name = "Adwaita";
        package = pkgs.gnome.adwaita-icon-theme;
        size = 24;

      };
      font = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
        size = 10;

      };

      gtk3.extraConfig = {
        gtk-cursor-theme-name = "Adwaita";
        gtk-cursor-theme-size = 24;
      };

      theme = {
        # name = "Adwaita-dark";
        name = "Flat-Remix-GTK-Blue-Dark";
        package = pkgs.flat-remix-gtk;

      };
    };
    qt = {
      enable = true;
      platformTheme = "gtk";
    };
    systemd.user.services = let
      # NOTE: for later reading:
      # https://pychao.com/2021/02/24/difference-between-partof-and-bindsto-in-a-systemd-unit/
      # NOTE: This makes sure that when both targets are stopped
      # then the service is also stopped.
      # Might redo this later.
      waylandChecker = pkgs.writeShellApplication {
        name = "waylandChecker.sh";
        text = ''
          hyprCheck=$(systemctl is-active --user --quiet hyprland-session.target)
          swayCheck=$(systemctl is-active --user --quiet sway-session.target)
          if [[ $hyprCheck  || $swayCheck ]]; then
            exit 0
          else
            systemctl stop --user shikane.service
          fi
        '';
      };
      # NOTE: THIS MIGHT BE WRONG. #2 this was wrong, after research,
      # only depend on graphical-session but start.
      # But only start after either hyprland or sway start.
      # TODO: (med prio) (research) investigate.
      weakTargets = ["hyprland-session.target" "sway-session.target"];
      strongTargets = ["graphical-session.target"];
      unitRules = {
        # NOTE: make sure that either hyprland or sway along with their
        # target units are started.
        # wants = weakTargets;
        After = weakTargets;
        Requisite = strongTargets;
        # PartOf = strongTargets;
      };
      # wantedRule = unitRules.After;
    in {
      ydotool = {
        Unit = {
          Description = "ydotool user service";
          Documentation = ["man:ydotool(1)"];
        };
        Service = {ExecStart = "${lib.getExe pkgs.ydotool}";};
        Install = {WantedBy = ["default.target"];};
      };
      shikane = {
        Unit =
          {
            Description = "Shikane service";
            Documentation = ["man:shikane(1)" "man:shikane(5)"];
          }
          // unitRules;
        Service = {
          ExecStart = "${lib.getExe pkgs.shikane}";
          Type = "simple";
          Restart = "always";
          Environment = [
            # TODO: (low prio) this is needed so that exec in shikane works,
            # need to investigate later why,
            # and if its isolated to my machine,home-manager,NixOS, or systemd.
            "PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
          ];
        };
        Install = {WantedBy = strongTargets;};
      };
      # for later reading
      # https://pychao.com/2021/02/24/difference-between-partof-and-bindsto-in-a-systemd-unit/
      dunst = { Unit = unitRules; };
    };
    dconf.settings = {
      #"org/gnome/desktop/interface" = {
      #cursor-size = 32;
      #text-scaling-factor = 1;
      #};
      "org/gnome/mutter" = {
        experimental-features = [ "scale-monitor-framebuffer" ];
      };
      "org/blueman/general" = { notification-daemon = false; };
    };
    xdg = {
      enable = true;
      configFile."hypr/hyprland.conf".text =
        import ./hyprland.conf.nix { inherit pkgs; };
      configFile."hypr/hyprlandd.conf".text =
        import ./hyprland.conf.nix { inherit pkgs; };
      configFile."waybar/" = {
        enable = true;
        source = ./waybar;
      };
      configFile."shikane/config.toml".text =
        import ../shikane/config.toml.nix { inherit config lib pkgs; };
    };
    services.dunst = {
      enable = true;
      package = pkgs.unstable.dunst;
    };
  };
}
