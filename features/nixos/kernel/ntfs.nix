{ pkgs, lib, config, ... }:
let kernel-mod = config.kernel.mod;
in {

  config = lib.mkIf kernel-mod.ntfs.enable {
    nixpkgs.overlays = [
      (self: super: {
        linuxPackages_6_2 = pkgs.linuxPackagesFor
          (super.linuxPackages_6_2.kernel.override {
            structuredExtraConfig = with lib.kernel; { NTFS3_FS = module; };
            ignoreConfigErrors = true;
          });
      })
    ];
  };
}
