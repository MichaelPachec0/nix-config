{ lib, ... }: {
  imports = [ ./programs.nix ];
  options = {
    graphical.enable =
      lib.mkEnableOption "Enable graphical programs common in all desktops";
    audio.enable =
      lib.mkEnableOption "Enable audio programs common in all desktops";
  };
}
