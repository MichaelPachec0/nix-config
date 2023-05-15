{ ... }: {
  disabledModules = [ "services/hardware/usbmuxd.nix" ];
  imports = [ ./usbmuxd.nix ];
}
