{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config;
in
  with lib;
  with builtins; rec {
    config = lib.mkIf (cfg.kernel.mod.native.enable) {
        nixpkgs.overlays = [
          (_final: prev: {
            linux-kernel = pkgs.linuxPackagesFor (prev.linux.override {
              NIX_CFLAGS_COMPILE = "-march=native -mtune=native -flto";
            });
            #        linux-kernel = pkgs.linuxPackagesFor
            #          (cfg.kernel.mod.kernelPkg.kernel.overrideAttrs (old: {
            #            CFLAGS = (old.CFLAGS or " ")
            #              + ''-march=native -mtune=native -flto"'';
            #          }));
            #extraMakeFlags = [ "-march=native" "-mtune=native" "-flto" ];
          })
        ];
        boot.kernelPackages = pkgs.linux-kernel;
      };
  }
