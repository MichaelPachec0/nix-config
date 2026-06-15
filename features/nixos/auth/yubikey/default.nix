{
  config,
  lib,
  ...
}: {
  imports = [./yubikey.nix];
  options = {
    yubikey = {enable = lib.mkEnableOption "Enables auth support in nixOS";};
  };
}
