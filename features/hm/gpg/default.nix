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

  graphical = config.xsession.enable || waylandEnabled;

  # One package, both frontends. nixpkgs builds pinentry-gnome3 with the
  # gnome3, curses and tty flavors in a single derivation, so it already
  # carries bin/pinentry-curses and bin/pinentry-tty next to the GTK3/GCR
  # bin/pinentry-gnome3 that bin/pinentry points at, and the gnome3 binary
  # falls back to curses when no display is reachable (ssh sessions, VTs).
  # Installing pinentry-curses alongside it would only duplicate
  # bin/pinentry-curses, which home-manager's buildEnv rejects as a
  # collision. Headless hosts get the curses-only build.
  pinentryPackage =
    if graphical
    then pkgs.pinentry-gnome3
    else pkgs.pinentry-curses;
in {
  # Put pinentry, pinentry-curses and pinentry-tty (plus pinentry-gnome3 on
  # graphical hosts) on PATH for callers other than gpg-agent.
  home.packages = [pinentryPackage];

  # TODO: (med prio) (research needed) Need to find how nix does a if "package is installed", need to find out why.
  programs.zsh.oh-my-zsh.plugins = lib.optionals (config.programs.gpg.enable
    && config.programs.zsh.enable
    && config.programs.zsh.oh-my-zsh.enable)
  ["gpg-agent"];
  home.file.".gnupg/gpg.conf".text = import ./gpg.conf.nix {};
  home.file.".gnupg/gpg-agent.conf".text = import ./gpg-agent.conf.nix {
    inherit pinentryPackage;
  };
  home.file.".gnupg/scdaemon.conf".text = import ./scdaemon.conf.nix {};
}
