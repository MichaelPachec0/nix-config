{
  pkgs,
  config,
  lib,
  ...
}: let
  intel = builtins.elem "kvm-intel" config.boot.kernelModules;
  amd = builtins.elem "kvm-amd" config.boot.kernelModules;
  cfg = config;
in {
  options = with lib; {
    vfio.enable = mkEnableOption "Configure for vfio.";
    kernel.patch.sm.enable =
      mkEnableOption
      "Kernel patch to workaround faulty FLR for Sillicon Motion nvme controllers.";
    kernel.patch.timer.enable = mkEnableOption "Kernel timer patch to workaround vmexits with rdtsc.";
    kernel.patch.noFlr.enable =
      mkEnableOption "Kernel patch to workaround cpu usb controllers not supporting FLR correctly.";
  };

  config = lib.mkIf (cfg.vfio.enable) {
    boot = {
      initrd.kernelModules =
        [ "vfio" "vfio_pci" "vfio_iommu_type1" "vfio_virqfd" ];

      kernelParams =
        ["iommu=pt" "kvm.ignore_msrs=1" "kvm.report_ignored_msrs=0"]
        ++ lib.optionals amd [
          "amd_iommu=on"
          "kvm_amd.npt=1"
          # NOTE: avic and nested do not currently work side by side yet, need to disable one or the other
          #
          "kvm_amd.avic=1"
          "kvm_amd.nested=1"
          "kvm_amd.sev=0"
        ]
        ++ lib.optionals intel [
          # TODO: (low prio) other options?
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
          # NOTE: overwritten so that we remove all mentions of QEMU.
          package = pkgs.qemu_full.overrideAttrs (old: rec {
            pname = "qemu-patched";
            version = "8.0.2";
            src = builtins.fetchurl {
              url = "https://download.qemu.org/qemu-${version}.tar.xz";
              sha256 = "19gn9jixr3mim03njna201aglg7wixb9ihz24m0pkrpv6paanq7h";
            };
            patches = (old.patches or []) ++ [./qemu-8.0.2.patch];
          });
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
    boot.kernelPatches =
      lib.optionals cfg.kernel.patch.sm.enable [
        {
          # NOTE: This is needed since one of the nvme's being passed is sm2622en based (ex920) it cannot be passed
          # unless this kernel patch is integrated.
          name = "SM2622en flr workaround";
          patch = ./sm2262-nvme-subsystem-reset.diff;
        }
      ]
      ++ lib.optionals cfg.kernel.patch.timer.enable [
        {
          # NOTE: this tries to patch rdtsc so it is harder to track vmexits.
          name = "Timer patches";
          patch = ./timer.patch;
        }
      ]
      ++ lib.optionals cfg.kernel.patch.noFlr.enable [
        {
          # NOTE: for passing cpu usb controllers, this makes it so it wont fail on complete vm reboot.
          name = "amd-noflr";
          patch = ./amd-noflr.patch;
        }
      ];
  };
}

