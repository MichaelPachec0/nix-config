{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [./swayidle.nix ./waybar];
  config = let
    hyprland = inputs.hyprland.packages.${pkgs.system};
    cfg = config;
  in {
    nixpkgs.overlays = [
    ];
    wayland.windowManager.hyprland = {
      enable = true;
      systemdIntegration = true;
      xwayland = {
        enable = true;
        hidpi = true;
      };
    };
    wayland.windowManager.sway = let
    in {
      enable = true;
      config = rec {
        modifier = "Mod4";
        terminal = "kitty";
        menu = "rofi -show combi -modes combi -combi-modes 'window,drun,run,ssh'";

        keybindings = let
          mod = modifier;
        in {
          # vim style navigation
          "${mod}+j" = "focus down";
          "${mod}+h" = "focus left";
          "${mod}+l" = "focus right";
          "${mod}+k" = "focus up";
        };
      };
      wrapperFeatures = {
        gtk = true;
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
