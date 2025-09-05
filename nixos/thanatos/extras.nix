{
  config,
  pkgs,
  lib,
  ...
}: {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.michael = ../../hm/home.nix;
  # home-manager.users.michael = { pkgs, ... }: {
  #   imports = [
  #     ../../hm/home.nix
  #   ];
  # };
}
