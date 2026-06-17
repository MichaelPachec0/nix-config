{
  inputs,
  lib,
  # config,
  pkgs,
  # true for `home-manager switch`; false when integrated as a NixOS module
  # (useGlobalPkgs), where the system owns nixpkgs/nix config. See
  # docs/hm-nixos-integration.md.
  standalone ? true,
  ...
}: let
  spicetify = inputs.spicetify;
  spicePkgs = spicetify.packages.${pkgs.stdenv.hostPlatform.system}.default;
  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-hard;
  fluffychat = pkgs.callPackage (
    {
      lib,
      fetchzip,
      fetchFromGitHub,
      imagemagick,
      libgbm,
      libdrm,
      flutter327,
      pulseaudio,
      makeDesktopItem,
      olm,
      targetFlutterPlatform ? "linux",
    }: let
      libwebrtcRpath = lib.makeLibraryPath [
        libgbm
        libdrm
      ];
      pubspecLock = lib.importJSON ./pubspec.lock.json;
    in
      flutter327.buildFlutterApplication (
        rec {
          pname = "fluffychat-${targetFlutterPlatform}";
          version = "1.25.1";

          src = fetchFromGitHub {
            owner = "krille-chan";
            repo = "fluffychat";
            tag = "v${version}";
            hash = "sha256-5hdFc4JPtTmNVUGTKVBiG7unGsc3NQQ3SJ9I63kfUVc=";
          };

          inherit pubspecLock;

          gitHashes = {
            flutter_web_auth_2 = "sha256-3aci73SP8eXg6++IQTQoyS+erUUuSiuXymvR32sxHFw=";
          };

          inherit targetFlutterPlatform;

          meta = with lib; {
            description = "Chat with your friends (matrix client)";
            homepage = "https://fluffychat.im/";
            license = licenses.agpl3Plus;
            mainProgram = "fluffychat";
            maintainers = with maintainers; [
              mkg20001
              gilice
            ];
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
            ];
            sourceProvenance = [sourceTypes.fromSource];
            inherit (olm.meta) knownVulnerabilities;
          };
        }
        // lib.optionalAttrs (targetFlutterPlatform == "linux") {
          nativeBuildInputs = [imagemagick];

          runtimeDependencies = [pulseaudio];

          env.NIX_LDFLAGS = "-rpath-link ${libwebrtcRpath}";

          desktopItem = makeDesktopItem {
            name = "Fluffychat";
            exec = "fluffychat";
            icon = "fluffychat";
            desktopName = "Fluffychat";
            genericName = "Chat with your friends (matrix client)";
            categories = [
              "Chat"
              "Network"
              "InstantMessaging"
            ];
          };

          postInstall = ''
            FAV=$out/app/fluffychat-linux/data/flutter_assets/assets/favicon.png
            ICO=$out/share/icons

            install -D $FAV $ICO/fluffychat.png
            mkdir $out/share/applications
            cp $desktopItem/share/applications/*.desktop $out/share/applications
            for size in 24 32 42 64 128 256 512; do
              D=$ICO/hicolor/''${s}x''${s}/apps
              mkdir -p $D
              convert $FAV -resize ''${size}x''${size} $D/fluffychat.png
            done

            patchelf --add-rpath ${libwebrtcRpath} $out/app/fluffychat-linux/lib/libwebrtc.so
          '';
        }
        // lib.optionalAttrs (targetFlutterPlatform == "web") {
          prePatch =
            # https://github.com/krille-chan/fluffychat/blob/v1.17.1/scripts/prepare-web.sh
            let
              # Use Olm 1.3.2, the oldest version, for FluffyChat 1.14.1 which depends on olm_flutter 1.2.0.
              olmVersion = pubspecLock.packages.flutter_olm.version;
              olmJs = fetchzip {
                url = "https://github.com/famedly/olm/releases/download/v${olmVersion}/olm.zip";
                stripRoot = false;
                hash = "sha256-Vl3Cp2OaYzM5CPOOtTHtUb1W48VXePzOV6FeiIzyD1Y=";
              };
            in ''
              rm -r assets/js/package
              cp -r '${olmJs}/javascript' assets/js/package
            '';
        }
      )
  ) {};

  # Plugins beyond the NvChad default set, materialised into lazy.nvim's local
  # search path via programs.nvchad.extraLazyPlugins below. These are only
  # *installed* here; their lua config is managed separately in the nvim config.
  # (Moved out of the old features/hm/neovim/nixneovim.nix, where the list had
  # been parked behind `in []`.)
  nvchadExtraPlugins =
    (with pkgs.vimPlugins; [
      fidget-nvim # for notifications

      # Rust
      rustaceanvim # rust-tools successor
      crates-nvim # rust
      telescope-dap-nvim # debug view for telescope

      # Lua/neovim lua stuff
      neodev-nvim
      nvim-luadev

      # nix
      vim-nix # nix highlight
      vim-nixhash

      # Debug
      nvim-dap # debug support
      nvim-dap-ui # debug views for neovim
      nvim-nio # for nvim-dap
      lsp-format-nvim
      nvim-dap-virtual-text # show debug info inline

      # misc
      telescope-undo-nvim # visualize undo actions
      orgmode # org mode in vim
      telescope-media-files-nvim
      telescope-github-nvim
      telescope-cheat-nvim # for tldr in neovim
      telescope-manix # nixpkgs docs search in telescope
      hop-nvim # semantic cursor pointing
      hydra-nvim
      telescope-fzf-writer-nvim # fzf in nvim
      telescope-fzf-native-nvim # fzf in nvim
      nui-nvim # floating windowing ui in nvim
      neoconf-nvim
      inc-rename-nvim # lsp rename
      barbecue-nvim # vscode bar for nvim
      lspsaga-nvim # lsp helper plugin
      nvim-navic
      nvim-web-devicons
      # NOTE: dropbar-nvim used to come from the nixneovim overlay (now removed).
      # If eval reports it missing from stock nixpkgs, drop or replace it.
      dropbar-nvim
      telescope-ui-select-nvim # ui select support for telescope
      sqlite-lua
      nvim-treesitter-context # shows location in program structure
      actions-preview-nvim
      dressing-nvim # draw ui elements on top of buffers (e.g. LSP rename)
      trouble-nvim # colorful diagnostics/lsp/telescope
      todo-comments-nvim # colorful todo comments
      nvim-lightbulb # lightbulb hints when a line is actionable
      lsp-inlayhints-nvim
      vim-wakatime # time-tracker
      null-ls-nvim # code action/lint/diagnostics configurator
      harpoon # mark files for later use
      vim-visual-multi # multi cursor

      # ai
      ChatGPT-nvim
      windsurf-vim

      osv-nvim

      # testing
      neotest
      neotest-rust
      neotest-python
      neotest-plenary
      neotest-go
      neotest-elixir
      neotest-dart
      neotest-deno
      neotest-haskell
      neotest-gtest

      elixir-tools-nvim
      clangd_extensions-nvim
      telescope-file-browser-nvim
      telescope-project-nvim
      telescope-live-grep-args-nvim
      telescope-frecency-nvim

      yankring # synchronize yank/delete between vim instances
      windows-nvim # auto-resizing of windows
      lazygit-nvim
      git-nvim
      ts-software-licenses-nvim
      minimap-vim
      cmp-tabnine
      none-ls-extras-nvim

      # Custom plugins from helpers/overlays.nix (the `local` vim-plugins overlay).
      stay-centered # keeps cursor centered whenever possible
      virt-column # show char on colorcolumn
      vimBeGood # game inside vim to practice motions
      indentmini # show indentations using nvim decoration api
      wtf-nvim
      nvim-dap-repl-highlights
      neoai-nvim
      telescope-docker-nvim
      nvim-emmet
      kitty-scrollback-nvim
      clear-action-nvim
      (pkgs.vimUtils.buildVimPlugin {
        pname = "none-ls.nvim";
        version = "2025-02-24";
        src = inputs.none-ls;
        # none-ls (null-ls fork) needs plenary on the rtp for its require-check.
        dependencies = [plenary-nvim];
        # these diagnostics builtins can't be required standalone (they reference
        # external linters); skip them in the check, as nixpkgs does for none-ls.
        nvimSkipModules = [
          "null-ls.builtins.diagnostics.sqruff"
          "null-ls.builtins.diagnostics.sqlfluff"
          "null-ls.builtins.diagnostics.kube_linter"
          "null-ls.builtins.diagnostics.phpmd"
          "null-ls.builtins.diagnostics.twigcs"
        ];
      })
      inlay-hints-nvim
      guihua-lua
      pfp-vim
      cspell-nvim
      render-markdown-nvim
    ])
    ++ (with pkgs.master.vimPlugins; [
      typescript-tools-nvim
      godbolt-nvim
      (pkgs.master.vimPlugins.go-nvim.overrideAttrs (old: {
        checkInputs =
          (with pkgs; [
            guihua-lua
            nvim-lspconfig
          ])
          ++ old.checkInputs;
        doCheck = false;
      }))
    ]);
in {
  imports = [
    # spicetify.homeManagerModule
    ../features/hm/gpg
    ../features/hm/kanshi
    ../features/hm/zsh
    ../features/hm/kitty
    ../features/hm/ssh
    ../features/hm/common
    ../features/hm/wayland
    ../features/hm/virtualization
    ../helpers/caches.nix
    inputs.claude-for-linux.homeManagerModules.default
    # neovim (NvChad) + cspell now live in flake-playground; see programs.nvchad
    # / programs.cspell below.
    inputs.flake-playground.homeManagerModules.nvchad
    inputs.flake-playground.homeManagerModules.cspell
  ];
  # Only applied for standalone HM; when integrated (useGlobalPkgs) the system pkgs
  # already carry this overlay via helpers/overlays.nix hmIntegrationOverlays.
  nixpkgs.overlays = lib.mkIf standalone [
    inputs.claude-code.overlays.default
  ];
  # The system owns nix config when integrated as a NixOS module.
  nix = lib.mkIf standalone {
    package = pkgs.nix;
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;

      # access-tokens = github.com=***GITHUB-TOKEN-REMOVED***
    };
  };
  home = {
    username = "michael";
    homeDirectory = "/home/michael";
    sessionVariables = {
    };
  };
  # NOTE: this is for testing.
  systemd.user.sessionVariables = {
  };
  # {}
  # programs.nixneovim.nvchad.enable = true;
  home.packages = let
    # fastanime = pkgs.fastanime.overrideAttrs (old: {
    #   # TODO: add fzf to 
    #   propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ [pkgs.fzf];
    # });
  in with pkgs; [
    fastanime
    claude-code
    # fluffychat
  ];

  services.udiskie = {
    enable = true;
    automount = true; 
    notify = true;
    tray = "always";
    package = pkgs.udiskie;
  };
  programs.claude-desktop = {
    enable = true;
    fhs = true;  # FHS wrapper for MCP compatibility
  };

  # NvChad + neovim, from flake-playground's homeManagerModules.nvchad. The
  # module's defaults carry the full NvChad runtime set (cmp/treesitter/
  # telescope/lsp/...) and drive stock programs.neovim; extraLazyPlugins adds the
  # plugins formerly parked in features/hm/neovim. cspell config comes from the
  # sibling homeManagerModules.cspell.
  programs.nvchad = {
    enable = true;
    extraLazyPlugins = nvchadExtraPlugins;
    extraConfig = ''
	dofile(vim.fn.stdpath "config" .. "/nv/init.lua")
    '';
  };
  programs.cspell.enable = true;
  # Preserve the aliases/defaultEditor the old nixneovim config set (these merge
  # into the programs.neovim the nvchad module already enables).
  programs.neovim = {
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  graphical.enable = true;
  audio.enable = true;
  devMachine.enable = true;
  report-changes.enable = true;
  home.sessionPath = [
  "$HOME/.local/bin"
  ];

  xdg = {
    enable = true;
    dataFile = {
      lockscreen = {
        source = ../assets/img/consent-web-1920.png;
        target = "lockscreen.png";
      };
    };
  };

  # programs.spicetify = {
  #   enable = false;
  #   # spicetifyPackage = pkgs.spicetify-cli;
  #   # spotifyPackage = pkgs.spotify;
  #   # NOTE: This can be used when trying to calculate the vendor hash of a overlayed package.
  #   # used: nix-prefetch --file 'fetchTarball "channel:nixos-unstable"' '{ sha256 }: (spicetify-cli.overrideAttrs(old: rec { version = "2.18.1"; pname = old.pname; src = builtins.fetchGit { url = "https://github.com/${old.src.owner}/${pname}"; rev = "v${version}"; sha256 = "sha256-BZuvuvbFCZ6VaztlZhlUZhJ7vf4W49mVHiORhH8oH2Y="; }; })).go-modules.overrideAttrs (_: { modSha256 = sha256; })'
  #   # TODO: (low prio) Try to generalize this command so that boilerplate can be reduced to a minimum
  #   # vendorHash = "sha256-mAtwbYuzkHUqG4fr2JffcM8PmBsBrnHWyl4DvVzfJCw=";
  #   # ideally it should be nix-generate-goVendorHash {url} {rev}
  #   # similar to nix-prefetch-git {url} {rev}
  #
  #   windowManagerPatch = true;
  #   # HACK: this was used previously when lastest spotify would not work well in wayland (xwayland would work). As of now it
  #   # works good enough to not be needed.
  #   # TODO: (low prio) remove commented out code. This is now unneeded.
  #
  #   # spotifyPackage = pkgs.unstable.spotify.overrideAttrs (old: rec {
  #   #      version = "1.1.99.878.g1e4ccc6e";
  #   #      pname = "spotify";
  #   #      rev = "62";
  #   #      src = pkgs.fetchurl {
  #   #        url =
  #   #          "https://api.snapcraft.io/api/v1/snaps/download/pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7_${rev}.snap";
  #   #        sha512 =
  #   #          "339r2q13nnpwi7gjd1axc6z2gycfm9gwz3x9dnqyaqd1g3rw7nk6nfbp6bmpkr68lfq1jfgvqwnimcgs84rsi7nmgsiabv3cz0673wv";
  #   #      };
  #   #
  #   #      unpackPhase = ''
  #   #        runHook preUnpack
  #   #        unsquashfs "$src" '/usr/share/spotify' '/usr/bin/spotify' '/meta/snap.yaml'
  #   #        cd squashfs-root
  #   #        if ! grep -q 'grade: stable' meta/snap.yaml; then
  #   #          # Unfortunately this check is not reliable: At the moment (2018-07-26) the
  #   #          # latest version in the "edge" channel is also marked as stable.
  #   #          echo "The snap package is marked as unstable:"
  #   #          grep 'grade: ' meta/snap.yaml
  #   #          echo "You probably chose the wrong revision."
  #   #          exit 1
  #   #        fi
  #   #        if ! grep -q '${version}' meta/snap.yaml; then
  #   #          echo "Package version differs from version found in snap metadata:"
  #   #          grep 'version: ' meta/snap.yaml
  #   #          echo "While the nix package specifies: ${version}."
  #   #          echo "You probably chose the wrong revision or forgot to update the nix version."
  #   #          exit 1
  #   #        fi
  #   #        runHook postUnpack
  #   #      '';
  #   #    });
  #   #spotifyPackage = pkgs.unstable.spotify;
  #   enabledExtensions = with spicePkgs.extensions; [
  #     copyToClipboard
  #     showQueueDuration
  #     fullAppDisplay
  #     {
  #       filename = "genre.js";
  #       src = pkgs.fetchFromGitHub {
  #         owner = "jeroentvb";
  #         repo = "spicetify-genre";
  #         rev = "f503568af59f9b5b14c7751f44c8e0b1bb86b6b5";
  #         hash = "sha256-huN/1PDX5yzCdt+2yoVRrecv+zU59VG7f5ERnt62Sl8=";
  #       };
  #     }
  #     # INFO: example for manually defined extension.
  #     # {
  #     #   filename = "playlist-icons.js";
  #     #   src = pkgs.fetchFromGitHub {
  #     #     owner = "jeroentvb";
  #     #     repo = "spicetify-playlist-icons";
  #     #     rev = "4e2fdda5079b441eca8d4d9f7479db82f6cc20b8";
  #     #     sha256 = "1wiq1iq74g2y8g0yv5ldhf0dc7nnamr1ydfbb6fgq0c0ix3yrh51";
  #     #   };
  #     # }
  #     # {
  #     #   # HACK: powerbar does not work yet when specified from spicePkgs. Manually define it instead
  #     #
  #     #   filename = "power-bar.js";
  #     #   src = pkgs.fetchFromGitHub {
  #     #     owner = "jeroentvb";
  #     #     repo = "spicetify-power-bar";
  #     #     rev = "2044217153d070aab3a93bda796177e61e6c4a65";
  #     #     hash = "sha256-ELTfhkqPusEzCwjopd7aXuo5loG14chg50nuMjkzYSI=";
  #     #   };
  #     # }
  #     power-bar
  #     playlist-icons
  #
  #     trashbin
  #     seekSong
  #     fullAlbumDate
  #     skipStats
  #     history
  #     # genre
  #     bookmark
  #     loopyLoop
  #     adblock
  #     songStats
  #     wikify
  #     goToSong
  #   ];
  #   # Custom apps dont work on rolling release spotify,
  #   enabledCustomApps = with spicePkgs.apps; [
  #     # INFO: example when manually defining a plugin.
  #     marketplace
  #     reddit
  #     new-releases
  #     lyrics-plus
  #     eternal-jukebox
  #     spicetify-stats
  #     # INFO: found using the following command:
  #     # nix-prefetch-git https://github.com/Pithaya/spicetify-apps-dist --branch-name "dist/eternal-jukebox" <HASH>
  #     # {
  #     #   name = "eternal-jukebox";
  #     #   src = pkgs.fetchFromGitHub {
  #     #     owner = "Pithaya";
  #     #     repo = "spicetify-apps-dist";
  #     #     rev = "e5f52022e159b1f7c920e956d48c830903090d93";
  #     #     hash = "sha256-sGuyKH1V/MZaB1Jc/t3tsfRr0iylbBBFbYVk0AcPzGI=";
  #     #     # sha256 = "0i5qbrwxx7rx2yij8iadrmqz937j0rfsf3s17nr7b0f985vhzh99";
  #     #   };
  #     #   appendName = false;
  #     # }
  #     # {
  #     #   name = "spicetify-stats";
  #     #   src = pkgs.fetchFromGitHub {
  #     #     owner = "harbassan";
  #     #     repo = "spicetify-stats";
  #     #     rev = "c0e8668a742edc47622cc6fb40cca0ff54bd0554";
  #     #     hash = "sha256-w7gZ/F/AfgEd+KSOKivFjTnb3BNvZq1Md6qlV5fGhBI=";
  #     #   };
  #     #   appendName = false;
  #     # }
  #     # {
  #     #   name = "spicetify-beat-saber";
  #     #   src = pkgs.fetchzip {
  #     #     url = "https://github.com/kuba2k2/spicetify-beat-saber/releases/download/v2.1.1/beatsaber-dist-2.1.1.zip";
  #     #     hash = "sha256-DiCR0jx/oAnmNZKriDz09bGKDCVW9h78JWLT5TCoOXI=";
  #     #   };
  #     #   appendName = false;
  #     # }
  #   ];
  #   # TODO: (very low prio) change to using nix-colors
  #   # NOTE: previously dynamic was slow rendering, making it useless on a 4k display (still usuable on 1080p), transitioned to
  #   # a gruvbox like theme instead.
  #   # theme = spicePkgs.themes.Onepunch;
  #   theme = spicePkgs.themes.text;
  #   colorScheme = "gruvbox";
  # };
  xdg.desktopEntries = let
    experimental-gpu = "--ignore-gpu-blacklist --enable-gpu-rasterization --enable-native-gpu-memory-buffers --use-vulkan --enable-angle-features";
  in {
    spotify = {
      name = "Spiced Spotify";
      # exec = "spotify --ozone-platform-hint=auto --uri=%U";

      # PATH=/run/wrappers/bin:/home/michael/.nix-profile/bin:/etc/profiles/per-user/michael/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin sh -c "
      # exec = ''
      #   spotify --ozone-platform-hint=auto --enable-zero-copy --use-gl=desktop %U
      # spotify --no-zygote --no-sandbox --ozone-platform-hint=auto --enable-zero-copy --single-process --use-angle=vulkan --uri=%U
      # '';
      # exec = ''
      #   spotify --no-zygote --no-sandbox --ozone-platform-hint=auto --enable-zero-copy --single-process --uri=%U
      # '';VaapiVideoDecoder
      exec = ''
        spotify --enable-features=VaapiVideoDecoder  --no-zygote --no-sandbox --ozone-platform-hint=auto --enable-zero-copy --single-process ${experimental-gpu} --uri=%U
      '';
      icon = "spotify-client";
      type = "Application";
      terminal = false;
      genericName = "Music Player";
      comment = "Spotify streaming music client";
      categories = [
        "Audio"
        "Music"
        "Player"
        "AudioVideo"
      ];
      mimeType = ["x-scheme-handler/spotify"];
      settings = {
        StartupWMClass = "spotify";
      };
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
    legcord = {
      name = "legcord";
      exec = ''
        legcord --enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer --ozone-platform=wayland --enable-zero-copy ${experimental-gpu}
      '';
      type = "Application";
    };
  };
  programs.ncspot = {
    enable = true;
    # package = null;
    package = pkgs.emptyDirectory;
    settings = {
      default_keybindings = true;
      # 1000MiB
      audio_cache_size = 2000;
      notify = true;
      use_nerdfont = true;
      keybindings = {
        "p" = "playpause";
        "Ctrl+d" = "move down 5";
        "Ctrl+u" = "move up 5";
        "gg" = "move top";
        "Shift+g" = "move bottom";
        # "Enter" = "playpause";
        "d" = "";
        "dd" = "delete";
        "s" = "stop";
        "Shift+s" = "save";
        "Esc" = "back";
      };
      theme = {
        background = "default";
        primary = "#a89984";
        secondary = "#928374";
        title = "#8ec07c";
        playing = "#689d6a";
        playing_bg = "#383838";
        playing_selected = "#ebdbb2";
        highlight = "#d5c4a1";
        highlight_bg = "#484848";
        error = "#fbf1c7";
        error_bg = "#cc241d";
        statusbar_progress = "#458588";
        statusbar_bg = "#282828";
        statusbar = "#98971a";
        cmdline = "#d5c4a1";
        cmdline_bg = "#383838";
        search_match = "#fabd2f";
      };
    };
  };
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    flags = [
      "--disable-up-arrow"
    ];
    settings = {
      auto_sync = true;
      sync_address = "https://atuin.michaelpacheco.org";
      sync_frequency = "10m";
      style = "full";
      enter_accept = false;
      keymap_mode = "vim-normal";
      filter_mode_shell_up_key_binding = "host";
      scroll_exits = false;
    };
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";
} 
