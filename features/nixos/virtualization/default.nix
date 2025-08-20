{
  pkgs,
  config,
  lib,
  ...
}: let
  # intel = builtins.elem "kvm-intel" config.boot.kernelModules;
  # amd = builtins.elem "kvm-amd" config.boot.kernelModules;
  cfg = config;
in {
  options = with lib; {
    virt = {
      alt.enable = mkEnableOption "Enable alt virtualisation options";
      vfio.enable = mkEnableOption "Configure for vfio.";
      arch = {
        intel.enable = mkEnableOption "Enable intel specific optimizations.";
        amd.enable = mkEnableOption "Enable amd specific optimizations.";
      };
    };
    kernel.patch.sm.enable =
      mkEnableOption
      "Kernel patch to workaround faulty FLR for Sillicon Motion nvme controllers.";
    kernel.patch.timer.enable = mkEnableOption "Kernel timer patch to workaround vmexits with rdtsc.";
    kernel.patch.noFlr.enable =
      mkEnableOption "Kernel patch to workaround cpu usb controllers not supporting FLR correctly.";
    kernel.patch.extras = mkOption {
      type = with types; listOf attrs;
      default = [];
      description = ''
        Extra patches to add. Warning this will make it so that kernel will always be compiled from source.
      '';
    };
  };
  # TODO: (low prio) refactor common options
  config = let
    amd = cfg.virt.arch.amd.enable;
    intel = cfg.virt.arch.intel.enable;
    # patches = map ({src: {}})
  in
    lib.mkMerge [
      (lib.mkIf cfg.virt.vfio.enable
        {
          boot = {
            # NOTE: as of 6.2.1 "vfio_virqfd" is now builtin to the kernel
            initrd.kernelModules = ["vfio" "vfio_pci" "vfio_iommu_type1"];

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
            podman = {
              enable = true;
              dockerCompat = true;
              defaultNetwork = {settings = {dns_enabled = true;};};
              enableNvidia = true;
            };
            libvirtd = {
              enable = true;
              allowedBridges = ["br-vm"];
              package = pkgs.libvirt;
              qemu = {
                # package = pkgs.legacy.qemu_full;
                # package = pkgs.legacy.qemu_full.overrideAttrs (old: {
                #   pname = "qemu-patched";
                #   version = "8.0.5";
                # });
                # package = pkgs.legacy.qemu.overrideAttrs (old: {
                #   pname = "qemu-patched";
                #   version = "8.0.5";
                #   # src = pkgs.pkgs.fetchurl {
                #   #   url = "https://download.qemu.org/qemu-${version}.tar.xz";
                #   #   hash = "sha256-cQwQEZjjNNR2Lu9l9km8Q/qKXddTA1VLis/sPrJfDlU=";
                #   #   # sha256 = "1rmvrgqjhrvcmchnz170dxvrrf14n6nm39y8ivrprmfydd9lwqx0";
                #   # };
                #   patches =
                #     (old.patches or [])
                #     ++ [
                #       (pkgs.pkgs.fetchpatch {
                #         url = "https://raw.githubusercontent.com/zhaodice/qemu-anti-detection/main/qemu-8.0.5.patch";
                #         hash = "sha256-HsuZAJ3EZiGQRuFncX6rcmGhyhj8DJhSSBCy5UaaVcY=";
                #         # hash = "sha256-oBrX+eyY69c6sOhyFzmFC868OqvzomIuerqOyDYsEe8=";
                #         # hash = "sha256-N+3YRvOwIu+k1d0IYxwV6zWmfJT9jle38ywOWTbgX8Y=";
                #       })
                #     ];
                # });
                package = pkgs.qemu.overrideAttrs (old: rec {
                  pname = "qemu-patched";
                  version = "8.2.0";
                  src = pkgs.pkgs.fetchurl {
                    url = "https://download.qemu.org/qemu-${version}.tar.xz";
                    hash = "sha256-vwDS+hIBDfiwrekzcd71jmMssypr/cX1oP+Oah+xvzI=";
                  };
                  nativeBuildInputs = with pkgs;
                    [
                      makeWrapper
                      removeReferencesTo
                      pkg-config
                      flex
                      bison
                      dtc
                      meson
                      ninja

                      # Don't change this to python3 and python3.pkgs.*, breaks cross-compilation
                      python3Packages.python
                      python3Packages.sphinx
                      python3Packages.sphinx-rtd-theme
                      python3Packages.distutils
                    ]
                    ++ (with pkgs; [wrapGAppsHook]);
                  patches =
                    # (old.patches or [])
                    [
                      ./fix-qemu-ga.patch

                      # QEMU upstream does not demand compatibility to pre-10.13, so 9p-darwin
                      # support on nix requires utimensat fallback. The patch adding this fallback
                      # set was removed during the process of upstreaming this functionality, and
                      # will still be needed in nix until the macOS SDK reaches 10.13+.
                      ./provide-fallback-for-utimensat.patch
                      # Cocoa clipboard support only works on macOS 10.14+
                      ./revert-ui-cocoa-add-clipboard-support.patch
                      # Standard about panel requires AppKit and macOS 10.13+
                      (pkgs.fetchpatch {
                        url = "https://gitlab.com/qemu-project/qemu/-/commit/99eb313ddbbcf73c1adcdadceba1423b691c6d05.diff";
                        sha256 = "sha256-gTRf9XENAfbFB3asYCXnw4OV4Af6VE1W56K2xpYDhgM=";
                        revert = true;
                      })
                      # Workaround for upstream issue with nested virtualisation: https://gitlab.com/qemu-project/qemu/-/issues/1008
                      (pkgs.fetchpatch {
                        url = "https://gitlab.com/qemu-project/qemu/-/commit/3e4546d5bd38a1e98d4bd2de48631abf0398a3a2.diff";
                        sha256 = "sha256-oC+bRjEHixv1QEFO9XAm4HHOwoiT+NkhknKGPydnZ5E=";
                        revert = true;
                      })
                      (pkgs.fetchpatch {
                        url = "https://raw.githubusercontent.com/zhaodice/qemu-anti-detection/main/qemu-${version}.patch";
                        hash = "sha256-RG4lkSWDVbaUb8lXm1ayxvG3yc1cFdMDP1V00DA1YQE=";
                      })
                    ];
                });
                # ovmf = {
                #   enable = true;
                #   packages = with pkgs; [
                    # NOTE: OVMFFull DOES NOT WORK ON MY SYSTEM FOR SOME REASON < DEBUG ASAP
                    # VM WONT BOOT WITH CSM ENABLED
                    # TODO: (low prio) seperate fd's for all the options, or at least have the ability
                    # to use qemu's images for this
                    # NOTE: for todo: config currently works with specific ovmf images.
                    # TODO: (high prio) Decide if willing to commit images into repo.
                    # (pkgs.OVMFFull.override {csmSupport = false;}).fd
                    # begining w https://github.com/NixOS/nixpkgs/commit/4631f2e1ed2b66d099948665209409f2e8fc37ec csm was removed
                #     OVMFFull.fd
                #     legacy.pkgsCross.aarch64-multiplatform.OVMF.fd
                #   ];
                # };
                swtpm = {
                  enable = true;
                  package = pkgs.swtpm;
                };
              };
            };
          };
          environment.systemPackages = with pkgs; [pciutils virt-manager];

          # TODO: (high prio) rework edk2 firmware loading, rather than using these images, the centos images are
          # used because secure boot works. Need to find out if its possible to include it in this repo.
          environment.etc = {
            "ovmf/edk2-x86_64-secure-code.fd" = {
              source = "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-x86_64-secure-code.fd";
            };
            "ovmf/edk2-i386-vars.fd" = {
              source = "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-i386-vars.fd";
            };
            "rom/TU104_2080_vfio.rom" = {source = ./patched/TU104_2080_vfio.rom;};
            "virt/riscv/opensbi" = {
              source = "${pkgs.pkgsCross.riscv64.opensbi}";
            };
            "virt/riscv/uboot" = {
              source = "${pkgs.pkgsCross.riscv64.ubootQemuRiscv64Smode}";
            };
            "virt/qemu" = {
              source = "${pkgs.qemu}";
            };
            "virt/bad-csm" = {
              source = "${pkgs.OVMFFull.fd}";
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
            ++ cfg.kernel.patch.extras;
          # NOTE: not needed since 5.8!
          # ++ lib.optionals cfg.kernel.patch.noFlr.enable [
          #   {
          #     # NOTE: for passing cpu usb controllers, this makes it so it wont fail on complete vm reboot.
          #     name = "amd-noflr";
          #     patch = ./amd-noflr.patch;
          #   }
          # ];
        })
      (lib.mkIf cfg.virt.alt.enable {
        boot = {
          kernelParams = lib.optionals intel [
            # TODO: (low prio) other options?
            "kvm_intel.nested=1"
          ];
          kernelPatches = cfg.kernel.patch.extras;
        };
        virtualisation = {
          virtualbox.host = {
            enableExtensionPack = false;
            enable = false;
          };
          podman = {
            enable = true;
            dockerCompat = true;
            defaultNetwork = {settings = {dns_enabled = true;};};
          };
          # kvmgt = {enable = intel;};
          libvirtd = {
            enable = true;
            allowedBridges = ["br-vm"];
            qemu = {
              # ovmf = {
              #   enable = true;
              #   packages = [
              #     pkgs.OVMFFull.fd
              #     pkgs.legacy.pkgsCross.aarch64-multiplatform.OVMF.fd
              #   ];
              # };
              swtpm = {
                enable = true;
              };
            };
          };
        };
        # environment.systemPackages = with pkgs; [virt-manager];
        programs.virt-manager.enable = true;
        virtualisation.spiceUSBRedirection.enable = true;
        environment.etc = {
          "ovmf/edk2-x86_64-secure-code.fd" = {
            source = "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-x86_64-secure-code.fd";
          };
          "ovmf/edk2-x86_64-code.fd" = {
            source = "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-x86_64-code.fd";
          };
          "ovmf/edk2-i386-vars.fd" = {
            source = "${cfg.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-i386-vars.fd";
          };
          # NOTE: this is for booting riscv i.e getting fw_jump.bin and the u-boot.bin
          "riscv/opensbi" = {
            source = "${pkgs.stable.pkgsCross.riscv64.opensbi}";
          };
          "riscv/uboot" = {
            source = "${pkgs.stable.pkgsCross.riscv64.ubootQemuRiscv64Smode}";
          };
        };
      })
    ];
  # lib.mkIf cfg.virt.vfio.enable {
}
