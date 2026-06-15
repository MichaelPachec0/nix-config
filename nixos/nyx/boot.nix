
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
} @ args: let
# lanzaboote = inputs.lanzaboote {inherit pkgs;};
in {
  imports = [
    ../../features/nixos/kernel
    # TODO: move somewhere else
    # ../../features/nixos/usbip
    
  ];

  config = {
    boot = {
      loader = {
      systemd-boot = {
        enable = lib.mkForce false;
        memtest86.enable = true;
        consoleMode = "auto";
      };
      efi.canTouchEfiVariables = false;
      };
      lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
    };
    # NOTE: zen is a fast moving target, use kernel that updates less often.
    kernel.mod.kernelPkg = pkgs.linuxPackages_xanmod;
    # kernel.mod.kernelPkg = pkgs.linuxPackages_zen;
    kernel.mod.ntfs3.enable = false;
  };
}
