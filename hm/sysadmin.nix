{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ../features/hm/common
    ../features/hm/zsh
  ];
  home = {
    username = "sysadmin";
    homeDirectory = "/home/sysadmin";
  };
  home.packages = with pkgs; [
  ];
  systemd.user.sessionVariables = {
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";
}
