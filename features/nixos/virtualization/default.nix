{ pkgs, config, lib, ... }:
let
  intel = builtins.elem "kvm-intel" config.boot.kernelModules;
  amd = builtins.elem "kvm-amd" config.boot.kernelModules;
  cfg = config;
in {
  options = {
    vfio.enable = lib.mkEnableOption "Configure for vfio.";
    kernel.patch.sm.enable = lib.mkEnableOption
      "Kernel patch to workaround faulty FLR for Sillicon Motion nvme controllers.";
  };

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
        allowedBridges = [ "br-vm" ];
        package = pkgs.unstable.libvirt;
        qemu = {
          package = pkgs.unstable.qemu;
          ovmf = {
            enable = true;
            packages = [
              # NOTE: OVMFFull DOES NOT WORK ON MY SYSTEM FOR SOME REASON < DEBUG ASAP
              # VM WONT BOOT WITH CSM ENABLED
              # TODO: seperate fd's for all the options, or at least have the ability to use qemu's images for this
              (pkgs.unstable.OVMFFull.override { csmSupport = false; }).fd
              pkgs.pkgsCross.aarch64-multiplatform.OVMF.fd
            ];
          };
          swtpm = {
            enable = true;
            package = pkgs.unstable.swtpm;
          };
        };
      };
    };
    environment.systemPackages = with pkgs; [ pciutils virt-manager ];

    environment.etc = {
      "ovmf/edk2-x86_64-secure-code.fd" = {
        source =
          "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-x86_64-secure-code.fd";
      };
      "ovmf/edk2-i386-vars.fd" = {
        source =
          "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-i386-vars.fd";
      };
    };
    boot.kernelPatches = lib.optionals cfg.kernel.patch.sm.enable [
      {
        name = "SM2622en flr workaround";
        patch = ./sm2262-nvme-subsystem-reset.diff;
      }
      {
        name = "amd-noflr";
        patch = ./amd-noflr.patch;
      }
    ];
  };
}

