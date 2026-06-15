# Integrated home-manager for unstable hosts (the default). Adds the unstable
# home-manager NixOS module to the channel-agnostic core in ./common.nix.
# See docs/hm-nixos-integration.md.
{inputs, ...}: {
  imports = [
    ./common.nix
    inputs.home-manager.nixosModules.home-manager
  ];
}
