{
  lib,
  pkgs,
  config,
  ...
}: let
  kernel = config.kernel.mod.kernelPkg;
in {
  imports = [./ntfs.nix ./native.nix];
  options = {
    kernel = {
      mod = with lib; {
        kernelPkg = mkOption {
          description = "kernel being used";
          type = with types; raw;
          default = pkgs.linuxPackages;
        };
        ntfs3.enable = mkEnableOption "compiles ntfs3 support in the kernel";
        native.enable = mkEnableOption "compiles with native build flags.";
      };
    };
  };
  # since this is not defined in the config, set a default config when importing the module
  # TODO: (low prio) Find a better way of setting this in code.
  config = {boot.kernelPackages = lib.mkDefault kernel;};
}


    #     {
    #       command = "/run/current-system/sw/bin/env";
    #       options = [ "NOPASSWD" ];
    #     }
    #     {
    #       command = "/run/current-system/sw/bin/nix-env";
    #       options = [ "NOPASSWD" ];
    #     }
    #     {
    #       command = "/nix/store/*/bin/switch-to-configuration";
    #       options = [ "NOPASSWD" ];
    #     }
    #     {
    #       command = "/nix/store/*/activate-rs";
    #       options = [ "NOPASSWD" ];
    #     }
    #     {
    #       command = "/run/current-system/sw/bin/rm /tmp/deploy-rs-canary-*";
    #       options = [ "NOPASSWD" ];
    #     }
    #     {
    #       command = "/run/current-system/sw/bin/systemd-run -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER --collect --no-ask-password --pty --quiet --same-dir --service-type=exec --unit=nixos-rebuild-switch-to-configuration --wait true";
    #       options = [ "NOPASSWD" ];
    #     }
    #     {
    #       command = "/run/current-system/sw/bin/systemd-run -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER --collect --no-ask-password --pty --quiet --same-dir --service-type=exec --unit=nixos-rebuild-switch-to-configuration --wait /nix/store/*/bin/switch-to-configuration *";
    #       options = [ "NOPASSWD" ];
    #     }
    #   ];
    # }
    #
