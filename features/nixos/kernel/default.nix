{ lib, pkgs, config, ... }:
let kernel = config.kernel.mod.kernelPkg;
in {
  imports = [ ./ntfs.nix ./native.nix ];
  options = {
    kernel = {
      mod = with lib; {
        kernelPkg = mkOption {
          description = "kernel being used";
          type = with types; raw;
          default = pkgs.linuxPackages;
        };
        ntfs.enable = mkEnableOption "compiles ntfs3 support in the kernel";
        native.enable = mkEnableOption "compiles with native build flags.";
      };
    };
  };
  # since this is not defined in the config, set a default config when importing the module
  # TODO: Find a better way of setting this in code.
  config = { boot.kernelPackages = lib.mkDefault kernel; };
}
