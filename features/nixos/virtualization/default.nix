{ pkgs, config, lib, ... }:
let
  intel = builtins.elem "kvm-intel" config.boot.kernelModules;
  amd = builtins.elem "kvm-amd" config.boot.kernelModules;
  cfg = config;
in {
  options = { vfio.enable = lib.mkEnableOption "Configure for vfio."; };

  config = lib.mkIf (cfg.vfio.enable) {
    boot = {
      initrd.kernelModules =
        [ "vfio" "vfio_pci" "vfio_iommu_type1" "vfio_virqfd" ];

      kernelParams = lib.optionals (amd) [
        "amd_iommu=on"
        "kvm_amd.npt=1"
        "kvm_amd.avic=1"
        "kvm_amd.nested=1"
        "kvm.ignore_msrs=1"
        "kvm.report_ignored_msrs=0"
      ] ++ lib.optionals (intel) [
        # TODO: other options?
        "kvm_intel.nested=1"
      ];
    };
    virtualisation = {
      # as understood, since this will be headless and with no x11/wayland, ths will be unneeded

      libvirtd = {
        enable = true;
        qemu = {
          ovmf = {
            enable = true;
            packages =
              [ pkgs.OVMFFull.fd pkgs.pkgsCross.aarch64-multiplatform.OVMF.fd ];
          };
          swtpm = { enable = true; };
        };
      };
    };
    environment.systemPackages = with pkgs; [ libvirt qemu OVMFFull pciutils ];
  };
}

