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
    #
    # mkDefault so a host can diverge during a staged kernel rollout without
    # mkForce. Both hosts are meant to converge back onto one value here -- this
    # file is where the kernel is chosen for every host that imports it -- so a
    # live override in a host file is a temporary state, not the design.
    kernel.mod.kernelPkg = lib.mkDefault pkgs.linuxPackages_xanmod_stable;
    # kernel.mod.kernelPkg = pkgs.linuxPackages_zen;
    kernel.mod.ntfs3.enable = false;
  };
}
