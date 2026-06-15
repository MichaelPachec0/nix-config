{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (inputs) spicetify;
  spicePkgs = spicetify.packages.${pkgs.system}.default;
  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-hard;
in {
  imports = [
    spicetify.homeManagerModule
    ../features/hm/zsh
    ../features/hm/common
  ];

  home = {
    username = "michael";
    # NOTE: this is for testing
    homeDirectory = "/home/michael/home-temp/ubuntu";
  };

  programs.spicetify = {
    enable = true;
    spicetifyPackage = pkgs.spicetify-cli;
    windowManagerPatch = true;
    theme = spicePkgs.themes.Onepunch;
    colorScheme = "Base";
  };
  home.stateVersion = "23.11";
}
