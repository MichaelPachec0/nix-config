{inputs}: let
  overlays = import ./overlays.nix {inherit inputs;};

  # Single source of truth for the per-user home-manager module list, shared by:
  #   * flake.nix homeConfigurations.*   (standalone `home-manager switch`)
  #   * features/nixos/home              (integrated NixOS module, useGlobalPkgs)
  #
  # standalone = true  -> HM builds its own pkgs; overlays + nixpkgs.config are
  #                       applied inside HM via the homeManager* overlay modules
  #                       and the `standalone` guards in home.nix / common.
  # standalone = false -> NixOS provides pkgs (useGlobalPkgs = true); the overlay
  #                       delta is hoisted onto the system in features/nixos/home,
  #                       so here we pull in no extra overlay modules.
  mkHomeModules = {
    # primary per-user entrypoint, e.g. ./hm/home.nix or ./hm/sysadmin.nix
    entry,
    # extra per-host modules, e.g. [./hm/home-nyx.nix]
    perHost ? [],
    standalone ? true,
    desktop ? true,
    channel ? "unstable",
  }: let
    sets = overlays.${channel};
    overlayModules =
      if standalone
      then
        if desktop
        then sets.homeManagerDesktop
        else sets.homeManagerMinmal
      # integrated (useGlobalPkgs): overlays live on the system (hoisted by
      # features/nixos/home). The HM config needs no extra overlay modules - the
      # neovim/NvChad config now comes from flake-playground via the entry module.
      else [];
    # Previously imported inputs.hyprland.homeManagerModules.default (a small
    # shim that only set wayland.windowManager.hyprland.package). Dropped with
    # the Hyprland flake input: the package is now set directly in
    # features/hm/wayland/hyprland.nix (pkgs.latest.hyprland -> nixpkgs), and
    # the active HM module is home-manager's built-in one.
    desktopModules = [];
  in
    overlayModules ++ [entry] ++ desktopModules ++ perHost;
in {
  inherit mkHomeModules;
}
