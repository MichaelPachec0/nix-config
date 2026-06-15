# Integrated home-manager for stable hosts (servers). Adds the stable
# home-manager NixOS module to the channel-agnostic core in ./common.nix.
# Set `local.hm.channel = "stable"` on the host. See docs/hm-nixos-integration.md.
{inputs, ...}: {
  imports = [
    ./common.nix
    inputs.home-manager-stable.nixosModules.home-manager
  ];
}
