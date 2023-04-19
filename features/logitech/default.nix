{ config, lib, pkgs, ... }: {
  options = {
    services = {
      logid = { enable = lib.mkEnableOption "adds logid to the environment."; };
    };
  };
  config = let logid = config.logid.enable;
  in lib.mkIf logid {
    environment.systemPackages = with pkgs; [ logiops ];
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };
    systemd.packages = [ pkgs.logiops ];
  };
}
