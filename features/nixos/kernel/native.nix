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
    config = let
      optimizeWithFlags = pkg: flags:
        pkgs.lib.overrideDerivation pkg (old: let
          newflags = pkgs.lib.foldl' (acc: x: "${acc} ${x}") "" flags;
          oldflags =
            if (pkgs.lib.hasAttr "NIX_CFLAGS_COMPILE" old)
            then "${old.NIX_CFLAGS_COMPILE}"
            else "";
        in {NIX_CFLAGS_COMPILE = "${oldflags} ${newflags}";});

      optimizeForThisHost = pkg:
        optimizeWithFlags pkg ["-O3" "-march=native" "-fPIC"];
    in
      lib.mkIf (cfg.kernel.mod.native.enable) {
        nixpkgs.overlays = [
          (final: prev: {
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
