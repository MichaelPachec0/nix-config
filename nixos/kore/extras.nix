# Integrated home-manager for kore (stable server; user sysadmin; useGlobalPkgs).
#
# Server, so desktop = false: no hyprland/nixneovim and no overlay hoist --
# sysadmin.nix (common + zsh) references only plain nixpkgs (graphical/audio/
# devMachine are all off). The standalone path keeps working:
#   home-manager switch --flake .#sysadmin-kore
{...}: {
  imports = [../../features/nixos/home/stable.nix];
  local.hm = {
    enable = true;
    channel = "stable";
    user = "sysadmin";
    entry = ../../hm/sysadmin.nix;
    desktop = false;
  };
}
