{ config, lib, pkgs, inputs, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
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
      configFile."hypr/hyprland.conf".source = ./hyprland.conf;
      configFile."hypr/hyprlandd.conf".source = ./hyprland.conf;
      configFile."waybar/" = {
        enable = true;
        source = ./waybar;
      };
    };
    services.dunst = {
      enable = true;
      package = nw.dunst;

    };

  };
}
