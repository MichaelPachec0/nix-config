{ config, pkgs, lib, ... }:
let pinentryFlavor = if (config.xdg.portal.enable) then "gtk2" else "curses";
in {
  # TODO: Need to find how nix does a if "package is installed", need to find out why.
  programs.zsh.oh-my-zsh.plugins = lib.optionals (config.programs.gpg.enable
    && config.programs.zsh.enable && config.programs.zsh.oh-my-zsh.enable)
    [ "gpg-agent" ];
  home.file.".gnupg/gpg.conf".text = import ./gpg.conf.nix { };
  home.file.".gnupg/gpg-agent.conf".text = import ./gpg-agent.conf.nix {
    inherit pkgs;
    inherit pinentryFlavor;
  };
  home.file.".gnupg/scdaemon.conf".text = import ./scdaemon.conf.nix { };

}
