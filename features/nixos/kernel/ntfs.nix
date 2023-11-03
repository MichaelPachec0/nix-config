{ pkgs, lib, config, ... }:
let mod = config.kernel.mod;
in {

  config = lib.mkIf mod.ntfs3.enable {
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
