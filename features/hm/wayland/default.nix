{ config, lib, pkgs, inputs, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
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
    systemd.user.services = {
      shikane = {
        Unit = {
          Description = "Shikane service";
          Documentation = [ "man:shikane(1)" "man:shikane(5)" ];
          PartOf = [ "hyprland-session.target" ];
        };
        Service = { ExecStart = "${lib.getExe pkgs.shikane}"; };
      };
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
      configFile."shikane/config.toml".source = ../shikane/config.toml;
    };
    services.dunst = {
      enable = true;
      package = nw.dunst;

    };

  };
}
