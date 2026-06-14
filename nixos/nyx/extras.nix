# Integrated home-manager for nyx (useGlobalPkgs). See docs/hm-nixos-integration.md.
#
# The standalone path keeps working independently:
#   home-manager switch --flake .#michael-nyx
{...}: {
  imports = [../../features/nixos/home];
  local.hm = {
    enable = true;
    perHost = [../../hm/home-nyx.nix];
  };
}
