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
  #                       so here we only pull in the nixneovim HM *module* (its
  #                       options), not the overlay-applying wrappers.
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
      # integrated (useGlobalPkgs): overlays live on the system. Only a desktop
      # neovim config needs the nixneovim HM module's options; servers need none.
      else if desktop
      then [inputs.nixneovim.nixosModules.homeManager]
      else [];
    desktopModules =
      if desktop
      then [inputs.hyprland.homeManagerModules.default]
      else [];
  in
    overlayModules ++ [entry] ++ desktopModules ++ perHost;
in {
  inherit mkHomeModules;
}
