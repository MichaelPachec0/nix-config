{ inputs, lib, config, pkgs, ... }:
let
  spicePkgs = inputs.spicetify.packages.${pkgs.system}.default;
  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-hard;
in {
  imports = [
    inputs.hyrpland.homeManagerModules.default
    inputs.spicetify.homeManagerModule
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
  wayland.windowManager.hyrpland.enable = true;
}
