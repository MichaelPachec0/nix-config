# Integrated home-manager preset for the stable sysadmin servers (kore, selene, ...).
#
# Self-contained: import this from a server's module list to build the sysadmin
# home as part of the system. desktop = false -> no hyprland/nixneovim and no
# overlay hoist (sysadmin.nix references only plain nixpkgs). The standalone path
# keeps working (e.g. `home-manager switch --flake .#sysadmin-kore`).
# See docs/hm-nixos-integration.md.
{lib, ...}: {
  imports = [./stable.nix];
  local.hm = {
    enable = true;
    channel = lib.mkDefault "stable";
    user = lib.mkDefault "sysadmin";
    entry = lib.mkDefault ../../../hm/sysadmin.nix;
    desktop = lib.mkDefault false;
  };
}
