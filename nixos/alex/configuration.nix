# TODO: CHANGE! should i do disk encryption
# ask alex what items he wants installed in his config.
# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];
  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.grub.enable = false;
    system.stateVersion = "25.11";
  };
}
