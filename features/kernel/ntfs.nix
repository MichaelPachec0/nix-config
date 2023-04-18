{ pkgs, config, ... }: {

  boot.kernelPatches = [{
    name = "Enable ntfs3 kernel support";
    patch = null;
    extraConfig = "  NTFS3_FS m\n  NTFS3_LZX_XPRESS y\n";
  }];
}

