{ config, lib, pkgs, ... }: {
  imports = [ ./swayidle.nix ];
  config = {
    wayland.windowManager.hyprland = {
      enable = true;
      #package = pkgs.unstable.hyprland;
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
      unitRules = {
        After = [ "hyprland-session.target" ];
        Requisite = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
      };
      wantedRule = unitRules.After;
    in {
      ydotool = {
        Unit = {
          Description = "ydotool user service";
          Documentation = [ "man:ydotool(1)" ];
        };
        Service = { ExecStart = "${pkgs.ydotool}/bin/ydotoold"; };
        Install = { WantedBy = [ "default.target" ]; };
      };
      shikane = {
        Unit = {
          Description = "Shikane service";
          Documentation = [ "man:shikane(1)" "man:shikane(5)" ];
        } // unitRules;
        Service = {
          ExecStart = "${lib.getExe pkgs.unstable.shikane}";
          Type = "simple";
          Restart = "always";
          Environment = [
            # TODO: this is needed so that exec in shikane works, need to investigate later why, and if its isolated to my machine,home-manager,NixOS, or systemd.
            "PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
          ];
        };
        Install = { WantedBy = wantedRule; };
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
      package = nw.dunst;

    };

  };
}
