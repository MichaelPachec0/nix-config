{ inputs, lib, config, pkgs, ... }:
let
  spicePkgs = inputs.spicetify.packages.${pkgs.system}.default;
  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-hard;
in {
  imports = [
    inputs.hyprland.homeManagerModules.default
    inputs.spicetify.homeManagerModule
    ../features/auth/hm-gpg/yubikey.nix
    ../features/hm/kanshi
    ../features/hm/zsh
    ../features/hm/kitty
  ];
  nixpkgs = {
    overlays = [ ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };
  home = {
    username = "michael";
    homeDirectory = "/home/michael";
  };
  wayland.windowManager.hyprland = {
    enable = true;
    systemdIntegration = true;
    xwayland = {
      enable = true;
      hidpi = true;
    };
  };

  home.pointerCursor = {
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

  xdg = {
    enable = true;
    configFile."hypr/hyprland.conf".source = ./hyprland.conf;
  };
  # make sure that apps run under wayland when possible
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  # make sure vim is the default editor
  home.sessionVariables."EDITOR" = "vim";
  # HiDPI setup
  home.sessionVariables."GDK_SCALE" = 1;
  home.sessionVariables."GDK_DPI_SCALE" = 1;
  home.sessionVariables."QT_AUTO_SCREEN_SCALE_FACTOR" = 1;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
