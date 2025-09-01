{
  config,
  lib,
  pkgs,
  ...
}: {
  config = let
    cfg = config;
  in {
    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = ["qemu:///system"];
        uris = ["qemu:///system"];
      };
    };
  };
}
