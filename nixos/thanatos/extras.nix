# Integrated home-manager pilot for thanatos.
#
# Enable by uncommenting `./nixos/thanatos/extras.nix` in flake.nix's thanatos
# module list, then test BEFORE switching:
#   nix build .#nixosConfigurations.thanatos.config.system.build.toplevel
#
# The standalone path keeps working independently:
#   home-manager switch --flake .#michael-thanatos
{...}: {
  imports = [../../features/nixos/home];
  local.hm = {
    enable = true;
    perHost = [../../hm/home-thanatos.nix];
  };
}
