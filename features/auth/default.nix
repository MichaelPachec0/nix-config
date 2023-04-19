{ config, lib, ... }: {
  imports = [ ./yubikey ];
  options = {
    yubiAuth = {
      enable = lib.mkEnableOption
        "Enables gpg and u2f auth services using a yubikey in nixOS";
    };
  };
  config = lib.mkIf (config.yubiAuth.enable) { config.yubikey.enable = true; };
}
