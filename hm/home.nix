{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: let
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

  xdg = {
    enable = true;
    dataFile = {
      lockscreen = {
        source = ./consent-web-1920.png;
        target = "lockscreen.png";
      };
    };
  };

  programs.spicetify = {
    enable = true;
    spicetifyPackage = pkgs.unstable.spicetify-cli;
    # NOTE: This can be used when trying to calculate the vendor hash of a overlayed package.
    # used: nix-prefetch --file 'fetchTarball "channel:nixos-unstable"' '{ sha256 }: (spicetify-cli.overrideAttrs(old: rec { version = "2.18.1"; pname = old.pname; src = builtins.fetchGit { url = "https://github.com/${old.src.owner}/${pname}"; rev = "v${version}"; sha256 = "sha256-BZuvuvbFCZ6VaztlZhlUZhJ7vf4W49mVHiORhH8oH2Y="; }; })).go-modules.overrideAttrs (_: { modSha256 = sha256; })'
    # TODO: (low prio) Try to generalize this command so that boilerplate can be reduced to a minimum
    # vendorHash = "sha256-mAtwbYuzkHUqG4fr2JffcM8PmBsBrnHWyl4DvVzfJCw=";
    # ideally it should be nix-generate-goVendorHash {url} {rev}
    # similar to nix-prefetch-git {url} {rev}
    windowManagerPatch = true;
    # HACK: this was used previously when lastest spotify would not work well in wayland (xwayland would work). As of now it
    # works good enough to not be needed.
    # TODO: (low prio) remove commented out code. This is now unneeded.

    # spotifyPackage = pkgs.unstable.spotify.overrideAttrs (old: rec {
    #      version = "1.1.99.878.g1e4ccc6e";
    #      pname = "spotify";
    #      rev = "62";
    #      src = pkgs.fetchurl {
    #        url =
    #          "https://api.snapcraft.io/api/v1/snaps/download/pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7_${rev}.snap";
    #        sha512 =
    #          "339r2q13nnpwi7gjd1axc6z2gycfm9gwz3x9dnqyaqd1g3rw7nk6nfbp6bmpkr68lfq1jfgvqwnimcgs84rsi7nmgsiabv3cz0673wv";
    #      };
    #
    #      unpackPhase = ''
    #        runHook preUnpack
    #        unsquashfs "$src" '/usr/share/spotify' '/usr/bin/spotify' '/meta/snap.yaml'
    #        cd squashfs-root
    #        if ! grep -q 'grade: stable' meta/snap.yaml; then
    #          # Unfortunately this check is not reliable: At the moment (2018-07-26) the
    #          # latest version in the "edge" channel is also marked as stable.
    #          echo "The snap package is marked as unstable:"
    #          grep 'grade: ' meta/snap.yaml
    #          echo "You probably chose the wrong revision."
    #          exit 1
    #        fi
    #        if ! grep -q '${version}' meta/snap.yaml; then
    #          echo "Package version differs from version found in snap metadata:"
    #          grep 'version: ' meta/snap.yaml
    #          echo "While the nix package specifies: ${version}."
    #          echo "You probably chose the wrong revision or forgot to update the nix version."
    #          exit 1
    #        fi
    #        runHook postUnpack
    #      '';
    #    });
    #spotifyPackage = pkgs.unstable.spotify;
    enabledExtensions = with spicePkgs.extensions; [
      copyToClipboard
      showQueueDuration
      fullAppDisplay
      # INFO: example for manually defined extension.
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
      {
        name = "eternal-jukebox";
        src = pkgs.fetchFromGitHub {
          owner = "Pithaya";
          repo = "spicetify-apps-dist";
          rev = "ed97b5f85f646e0c5d5bf26b9bfc3f5baa52c6b0";
          sha256 = "0i5qbrwxx7rx2yij8iadrmqz937j0rfsf3s17nr7b0f985vhzh99";
        };
        appendName = false;
      }
      {
        name = "spicetify-stats";
        src = pkgs.fetchFromGitHub {
          owner = "harbassan";
          repo = "spicetify-stats";
          rev = "c0e8668a742edc47622cc6fb40cca0ff54bd0554";
          hash = "sha256-w7gZ/F/AfgEd+KSOKivFjTnb3BNvZq1Md6qlV5fGhBI=";
        };
        appendName = false;
      }
      {
        name = "spicetify-beat-saber";
        src = pkgs.fetchzip {
          url = "https://github.com/kuba2k2/spicetify-beat-saber/releases/download/v2.1.1/beatsaber-dist-2.1.1.zip";
          hash = "sha256-DiCR0jx/oAnmNZKriDz09bGKDCVW9h78JWLT5TCoOXI=";
        };
        appendName = false;
      }
    ];
    # spotify gruvbox theme
    theme = spicePkgs.themes.Onepunch;
  };
  xdg.desktopEntries = {
    spotify-dev = {
      name = "Spiced Dev Spotify";
      exec = ''
        ${pkgs.spicetify-cli}/bin/spicetify-cli enable-devtools
      '';
      icon = "spotify";
      type = "Application";
    };
    spotify = {
      name = "Spiced Spotify";
      # exec = "spotify --ozone-platform-hint=auto --uri=%U";
      # /run/wrappers/bin:/home/michael/.nix-profile/bin:/etc/profiles/per-user/michael/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin
      # HACK: DO NOT KNOW WHY THE HELL THIS WORKS.
      # TODO: (high prio) investigate why this works.

      # PATH=/run/wrappers/bin:/home/michael/.nix-profile/bin:/etc/profiles/per-user/michael/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin sh -c "
      exec = ''
        spotify --ozone-platform-hint=auto --enable-zero-copy --use-gl=desktop
      '';
      icon = "spotify";
      type = "Application";
    };
    checkEnv = {
      name = "printEnv";
      # exec = ''sh -c "env > ~/env.txt"'';
      exec = ''sh -c "PATH=/run/wrappers/bin:/home/michael/.nix-profile/bin:/etc/profiles/per-user/michael/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin env > ~/good-env.txt"'';
      type = "Application";
    };
    checkZEnv = {
      name = "printZEnv";
      exec = ''zsh -c "env > ~/zenv.txt"'';
      type = "Application";
    };
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
