{ lib, ... }: {
  imports = [ ./ntfs.nix ];
  options = {
    kernel-mod = {
      ntfs3 = {
        enable = lib.mkEnableOption "compiles ntfs3 support in the kernel";
      };
    };
  };
}
