{ inputs, lib, config, pkgs, ... }:
let
  spicePkgs = inputs.spicetify.packages.${pkgs.system}.default;
  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-hard;
in {
  imports = [
    inputs.hyprland.homeManagerModules.default
    inputs.spicetify.homeManagerModule
    ../features/hm/gpg
    ../features/hm/kanshi
    ../features/hm/zsh
    ../features/hm/kitty
    ../features/hm/ssh
    ../features/hm/common
    ../features/hm/neovim
    ../features/hm/wayland
  ];
  nixpkgs = {
    overlays = [ ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };
  home = {
    username = "michael";
    homeDirectory = "/home/michael";
  };

  graphical.enable = true;
  audio.enable = true;
  devMachine.enable = true;

  xdg = { enable = true; };
  # make sure that apps run under wayland when possible
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  # make sure vim is the default editor
  home.sessionVariables."EDITOR" = lib.mkForce "vim";
  # HiDPI setup
  home.sessionVariables."GDK_SCALE" = 1;
  home.sessionVariables."GDK_DPI_SCALE" = 1;
  home.sessionVariables."QT_AUTO_SCREEN_SCALE_FACTOR" = 1;
  programs.spicetify = {
    enable = true;
    windowManagerPatch = true;
    spotifyPackage = pkgs.unstable.spotify;
    #spotifyPackage = pkgs.spotify;
    # theming causes extreme slowdown in spotify, disable for now.
    # theme = spicePkgs.themes.DefaultDynamic;
    # colorScheme = 
    enabledExtensions = with spicePkgs.extensions; [
      copyToClipboard
      showQueueDuration
      fullAppDisplayMod
      # powerBar
      trashbin
      seekSong
      playlistIcons
      fullAlbumDate
      skipStats
      history
      genre
      fixEnhance
      bookmark
      loopyLoop
      # this is charliesAdblock
      adblock
      songStats
      wikify
      goToSong

    ];
    # Custom apps dont work on rolling release spotify,
    enabledCustomApps = with spicePkgs.apps; [
      marketplace
      reddit
      new-releases
      lyrics-plus
    ];

  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
