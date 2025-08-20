{ config, ... }:

{
    imports = [
        ./services.nix
    ];

    environment.systemPackages = with config.kernel.mod.kernelPkg; [
        usbip
    ];

    boot.kernelModules = [
        "vhci-hcd"
        "usbip_core"
        "usbip_host"
    ];
}
