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
    spotifyPackage = pkgs.unstable.spotify.overrideAttrs (old: rec {
      version = "1.1.99.878.g1e4ccc6e";
      pname = "spotify";
      rev = "62";
      src = pkgs.fetchurl {
        url =
          "https://api.snapcraft.io/api/v1/snaps/download/pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7_${rev}.snap";
        sha512 =
          "339r2q13nnpwi7gjd1axc6z2gycfm9gwz3x9dnqyaqd1g3rw7nk6nfbp6bmpkr68lfq1jfgvqwnimcgs84rsi7nmgsiabv3cz0673wv";
      };

      unpackPhase = ''
        runHook preUnpack
        unsquashfs "$src" '/usr/share/spotify' '/usr/bin/spotify' '/meta/snap.yaml'
        cd squashfs-root
        if ! grep -q 'grade: stable' meta/snap.yaml; then
          # Unfortunately this check is not reliable: At the moment (2018-07-26) the
          # latest version in the "edge" channel is also marked as stable.
          echo "The snap package is marked as unstable:"
          grep 'grade: ' meta/snap.yaml
          echo "You probably chose the wrong revision."
          exit 1
        fi
        if ! grep -q '${version}' meta/snap.yaml; then
          echo "Package version differs from version found in snap metadata:"
          grep 'version: ' meta/snap.yaml
          echo "While the nix package specifies: ${version}."
          echo "You probably chose the wrong revision or forgot to update the nix version."
          exit 1
        fi
        runHook postUnpack
      '';
    });
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
          rev = "3b7e0559e91e76975cca41bafdb4ea2990dd468a";
          sha256 = "05cmx0y69rghs4jwbq307xzn4jbdg9av9ddlq6mw911hgiz6gip2";
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
      {
        name = "marketplace";
        src = pkgs.fetchFromGitHub {
          owner = "spicetify";
          repo = "spicetify-marketplace";
          rev = "865ba27733c885a7a4c9ab9e4b896cd8dc8769d2";
          sha256 = "1xqkl37mw5jirm1ys4mmfp5qfc4zas9wzssfqag7q53qlj2j1v4n";
        };
        appendName = false;
      }
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
