{ config, lib, pkgs, ... }:
let cfg = config;
in {
  config = lib.mkIf (cfg.kernel.mod.native.enable) {
    nixpkgs.overlays = [
      (final: prev: {
        linux-kernel = final.linuxPackagesFor
          (cfg.kernel.mod.kernelPkg.override {
            extraMakeFlags = [ "-march=native" "-mtune=native" "-flto" ];
          });
      })
    ];
    boot.kernelPackages = pkgs.linux-kernel;
  };
}
