{
  pkgs,
  lib,
  config,
  ...
}: let
  mod = config.kernel.mod.ntfs3;
in {
  config = lib.mkIf mod.enable {
    nixpkgs.overlays = [
      (self: super: {
        # linuxPackages_6_2 =
        linuxPackages = 
          pkgs.linuxPackagesFor
          (super.linuxPackages.kernel.override {
            structuredExtraConfig = with lib.kernel; {NTFS3_FS = module;};
            ignoreConfigErrors = true;
          });
      })
    ];
  };
}
