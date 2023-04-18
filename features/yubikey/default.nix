{ config, lib, ... }:
let cfg = config.nixos;
in {
  options = {
    yubikey = { enable = lib.mkEnableOption "Enables auth support in nixOS"; };
  };
  config = lib.mkIf cfg.yubikey.enable { imports = [ ./yubikey.nix ]; };
}
