{
  config,
  pkgs,
  lib,
  ...
}: let
  cfgWM = config.wayland.windowManager;
  # generate a list of wayalnd window managers containing only enablement condition.
  # This assumes that only a attrset of window managers will be here.
  waylandWMList = lib.attrsets.mapAttrsToList (n: v: v.enable) cfgWM;
  # If there are any wm's enabled this will be true.
  # NOTE: findFirst accepts a function that returns a boolean, since this is just a list of booleans, a simple function
  # returning the value is enough
  waylandEnabled = lib.lists.findFirst (wm: wm) false waylandWMList;

  pinentryFlavor =
    if (config.xsession.enable || waylandEnabled)
    then "gtk2"
    else "curses";
in {
  # TODO: (med prio) (research needed) Need to find how nix does a if "package is installed", need to find out why.
  programs.zsh.oh-my-zsh.plugins = lib.optionals (config.programs.gpg.enable
    && config.programs.zsh.enable
    && config.programs.zsh.oh-my-zsh.enable)
  ["gpg-agent"];
  home.file.".gnupg/gpg.conf".text = import ./gpg.conf.nix {};
  home.file.".gnupg/gpg-agent.conf".text = import ./gpg-agent.conf.nix {
    inherit pkgs;
    inherit pinentryFlavor;
  };
  home.file.".gnupg/scdaemon.conf".text = import ./scdaemon.conf.nix {};
}
