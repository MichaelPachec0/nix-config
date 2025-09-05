{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
} @ args: let
  # yubikey-manager = pkgs.master.yubikey-manager;
  # thermald = pkgs.master.thermald.overrideAttrs (old: {
  #   patches =
  #     (old.patches or [])
  #     ++ [
  #       # NOTE: this to workaround thermald crashes on more recent kernels (last remember encountered on 6.5.9, also applies
  #       # on 6.6.0) thermald
  #       # ref: https://github.com/intel/thermal_daemon/pull/422
  #       ./stack-smash-thermald.patch
  #     ];
  # });
  yubikey-manager = pkgs.yubikey-manager;
  # NOTE: This is not needed anymore. This is for compat reasons.
  thermald = pkgs.thermald;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  config = {
    nixpkgs.overlays = [

# (self: super: super.linuxPackages.extend (lpself: lpsuper: {
#   mbp2018-bridge-drv = super.linuxPackages.mbp2018-bridge-drv.overrideAttrs (o: rec {
#     src =   pkgs.fetchFromGitHub {
#     owner = "klizas";
#     repo = "apple-bce-drv";
#     rev = "b607bd815af83d5c46ff08395c9b25c93b7fab00";
#     hash = "sha256-hMS7ZU04daJcgz4OpRBhLuUjqnoIr3q0vakNYAivQXk=";
#   };
#   });
#   ));
    ];
    boot.initrd.availableKernelModules = [
      # fast decrypt for luks
      "aesni_intel"

      "thunderbolt"
    ];
    # boot.initrd.kernelModules = [
    #   "i915"
    #   # for early decrypt on t2 macs
    #   "snd"
    #   "snd_pcm"
    #   "apple-bce"
    # ];

    boot.kernel.sysctl = {
      "dev.i915.perf_stream_paranoid" = 0;
    };
    boot.kernelParams = [
      # from: https://wiki.archlinux.org/title/Dell_XPS_15_(9560)#Enable_power_saving_features_for_the_i915_kernel_module

      # dec/enc support
      "i915.enable_guc=2"

      # Self explanatory
      "mitigations=off"
      # coffeelake change
      # "mem_sleep_default=deep"
    ];

    virt.arch.intel.enable = true;
    services.hardware.bolt.enable = true;
    hardware = {
      firmware = [
        (pkgs.stdenvNoCC.mkDerivation (final: {
          name = "brcm-firmware";
          src = ./rootdir/lib/firmware/brcm;
          installPhase = ''
            mkdir -p $out/lib/firmware/brcm
            cp ${final.src}/* "$out/lib/firmware/brcm"
          '';
        }))
      ];
      apple-t2 = {
        enableIGPU = true;
        kernelChannel = "latest";
      };
    };
    boot.loader = {
      # efi.efiSysMountPoint = "/boot"; # make sure to change this to your EFI partition!
      systemd-boot.enable = true;
    };
    boot.initrd.luks.devices."swap".device = "/dev/disk/by-uuid/c6fff77e-04d5-40a1-a7d1-e49ff83ca0ad";
    networking.hostName = "aphrodite"; # Define your hostname.
  };
}
