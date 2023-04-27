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
    spicetifyPackage = pkgs.unstable.spicetify-cli;
    windowManagerPatch = true;
    spotifyPackage = pkgs.unstable.spotify;
    # theming causes extreme slowdown in spotify on 4k, disable for now.
    #theme = spicePkgs.themes.DefaultDynamic;
    # TODO: change to using nix-colors
    # colorScheme = 
    enabledExtensions = with spicePkgs.extensions; [
      copyToClipboard
      showQueueDuration
      fullAppDisplay
      {
        filename = "power-bar.js";
        src = pkgs.fetchFromGitHub {
          owner = "jeroentvb";
          repo = "spicetify-power-bar";
          rev = "dacaffb55b8e06954e8b22ec4f23a597e795d83f";
          sha256 = "1m30k1j8023yy0n4ia6m95scyi29i88pmx4vyxk6rxr07p3b9c7x";
        };
      }
      {
        filename = "playlist-icons.js";
        src = pkgs.fetchFromGitHub {
          owner = "jeroentvb";
          repo = "spicetify-playlist-icons";
          rev = "4e2fdda5079b441eca8d4d9f7479db82f6cc20b8";
          sha256 = "1wiq1iq74g2y8g0yv5ldhf0dc7nnamr1ydfbb6fgq0c0ix3yrh51";
        };
      }
      trashbin
      seekSong
      fullAlbumDate
      skipStats
      history
      genre
      bookmark
      loopyLoop
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
