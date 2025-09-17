# HACK: This whole file is being used as a shim in the interim that hyprland flake is targeting nixpkgs-unstable, but needs mesa to be nixos stable
{
  inputs,
  # config,
  lib,
  pkgs,
  ...
}:
with lib; let
  # wlroots = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.wlroots-hyprland.override {
  # wlroots = pkgs.unstable.wlroots.override {
  #   inherit (pkgs) mesa;
  #   inherit (pkgs.unstable) wayland-protocols wayland-scanner;
  # };
  # };
  package =
    inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # .override
  # pkgs.hypr.default.override
  # {
  # HACK: use current mesa package.
  # inherit (pkgs) mesa;
  # inherit (pkgs.unstable) wayland-protocols wayland-scanner;
  # enableXWayland = true;
  # hidpiXWayland = true;
  # inherit wlroots;
  # };
  xdgPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland.override {
    # inherit (pkgs) mesa;
    # inherit (pkgs.unstable) wayland-protocols wayland-scanner;
    # hyprland-share-picker = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland-share-picker.override {
    hyprland = package;
    # };
  };
  # xdgPackage = pkgs.hypr.xdg-desktop-portal-hyprland.override {
  #   inherit (pkgs) mesa;
  #   # inherit (pkgs.unstable) wayland-protocols wayland-scanner;
  #   hyprland-share-picker = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland-share-picker.override {
  #     hyprland = package;
  #   };
  # };
in {
  disabledModules = ["programs/hyprland.nix"];
  config = {
    environment = {
      systemPackages = [
        package
      ];
      sessionVariables = {
        NIXOS_OZONE_WL = mkDefault "1";
      };
    };
    # WARN: future version of nixos will deprecate this option,  change to enabling the fonts themselves.
    # fonts.enableDefaultFonts = mkDefault true;
    # this changed from fonts.fonts to fonts.packages, might have to edit this when checking nixos version
    fonts.fonts = [
      pkgs.dejavu_fonts
      pkgs.freefont_ttf
      pkgs.gyre-fonts # TrueType substitutes for standard PostScript fonts
      pkgs.liberation_ttf
      pkgs.unifont
      pkgs.noto-fonts-emoji
    ];
    hardware.opengl.enable = mkDefault true;

    programs = {
      dconf.enable = mkDefault true;
      # xwayland.enable = mkDefault true;
    };

    security.polkit.enable = mkDefault true;

    services.xserver.displayManager.sessionPackages = [package];

    xdg.portal = {
      enable = mkDefault true;
      extraPortals = [xdgPackage];
    };
  };
}
