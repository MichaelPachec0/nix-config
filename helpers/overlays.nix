{inputs, ...}: let
  prepNixpkgs = _nixpkgs: system:
    import _nixpkgs {
      config.allowUnfree = true;
      inherit system;
    };
  mkOverlayModules = ov: ({
    config,
    pkgs,
    lib,
    ...
  }: {
    # nixpkgs.overlays = builtins.map (i: builtins.trace i i) ov;
    nixpkgs.overlays = ov;
  });
  channels = final: prev: {
    stable = prepNixpkgs inputs.nixpkgs-stable prev.stdenv.hostPlatform.system;
    unstable = prepNixpkgs inputs.nixpkgs prev.stdenv.hostPlatform.system;
    master = prepNixpkgs inputs.nixpkgs-master prev.stdenv.hostPlatform.system;
    legacy = prepNixpkgs inputs.nixpkgs-oldstable prev.stdenv.hostPlatform.system;
  };
  lspServers = let
    local = final: prev: {
      # NOTE: pkgs/emmet-ls is a WIP stub (npmDepsHash = lib.fakeHash) that does
      # not build; fall back to the nixpkgs emmet-language-server instead.
      autotools-language-server = prev.callPackage ../pkgs/autotools-ls {};
    };
  in [
    local
    inputs.nixd.overlays.default
  ];
  vimPluginsOverlayList = let
    local = final: prev: {
      neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (old: {
        lua = old.lua.override {
          packageOverrides = final': prev': {
            neotest = prev'.neotest.overrideAttrs (oa: {
              doCheck = false;
            });
          };
        };
      });
      vimPlugins =
        # TOOD: convert to vimPlugins extend
        prev.vimPlugins
        // {
          # neotest = prev.vimPlugins.neotest.overrideAttrs {
          #   doCheck = false;
          # };
          # TODO: (low prio) convert import to callPackage
          vimBeGood =
            prev.callPackage ../pkgs/vimPlugins/vim-be-good {};
          coc-lightbulb =
            prev.callPackage ../pkgs/vimPlugins/coc-lightbulb {};
          coc-elixir =
            prev.callPackage ../pkgs/vimPlugins/coc-elixir {};
          stay-centered =
            prev.callPackage ../pkgs/vimPlugins/stay-centered {};
          block-nvim =
            prev.callPackage ../pkgs/vimPlugins/block-nvim {};
          indentmini =
            prev.callPackage ../pkgs/vimPlugins/indentmini {};
          virt-column =
            prev.callPackage ../pkgs/vimPlugins/virt-column {};
          wtf-nvim =
            prev.callPackage ../pkgs/vimPlugins/wtf-nvim {};
          nvim-dap-repl-highlights =
            prev.callPackage ../pkgs/vimPlugins/nvim-dap-repl-highlights {};
          neoai-nvim =
            prev.callPackage ../pkgs/vimPlugins/neoai {};
          osv-nvim =
            prev.callPackage ../pkgs/vimPlugins/ossfv {};
          neotest-gtest = prev.callPackage ../pkgs/vimPlugins/neotest-gtest {};
          telescope-docker-nvim = prev.callPackage ../pkgs/vimPlugins/telescope-docker {};
          nvim-emmet = prev.callPackage ../pkgs/vimPlugins/nvim-emmet {};
          fermyon-spin = prev.callPackage ../pkgs/fermyon-spin;
          git-nvim = prev.callPackage ../pkgs/vimPlugins/git-nvim {};
          ts-software-licenses-nvim = prev.callPackage ../pkgs/vimPlugins/ts-software-license {};
          # kitty-scrollback-nvim = prev.callPackage ../pkgs/vimPlugins/kitty-scrollback {};
          fidget-nvim = prev.vimPlugins.fidget-nvim.overrideAttrs (old: {
            version = "2024-02-13-master";
            src = prev.fetchFromGitHub {
              owner = "j-hui";
              repo = "fidget.nvim";
              rev = "60404ba67044c6ab01894dd5bf77bd64ea5e09aa";
              hash = "sha256-cfoz2nGX7yzDLjTitposErJpC8EVX0DBy69kFKY0jps=";
            };
          });
          clear-action-nvim = prev.callPackage ../pkgs/vimPlugins/clear-action-nvim {};
          none-ls-nvim = prev.callPackage ../pkgs/vimPlugins/none-ls-nvim {};
          inlay-hints-nvim = prev.callPackage ../pkgs/vimPlugins/inlay-hints {};
          guihua-lua = prev.callPackage ../pkgs/vimPlugins/guihua-lua {};
          pfp-vim = prev.callPackage ../pkgs/vimPlugins/pfp-vim {};

          # sg-nvim =  inputs.sg.packages.${prev.stdenv.hostPlatform.system}.sg-nvim;
          inherit (inputs.sg.packages.${prev.stdenv.hostPlatform.system}) sg-nvim;
          # inherit (inputs.git-oxide.legacyPackages.${prev.stdenv.hostPlatform.system}) gitoxide;
          cspell-nvim = prev.callPackage ../pkgs/vimPlugins/cspell-nvim {};
          none-ls-extras-nvim = prev.callPackage ../pkgs/vimPlugins/none-ls-extras-nvim {};

          # go-nvim = prev.go-nvim.overrideAttrs (
          #   old: {
          #     checkInputs =
          #       (with prev; [
          #         guihua-lua
          #         nvim-lspconfig
          #         # nvim-treesitter
          #       ])
          #       ++ old.checkInputs;
          #     dependencies =
          #       (with prev; [
          #         guihua-lua
          #         nvim-lspconfig
          #       ])
          #       ++ old.dependencies;
          #     doCheck = false;
          #     # TODO: FIND OUT WHY THIS NEEDS FIXING
          #     nvimSkipModules = [
          #       "ts.utils"
          #       "fixplurals"
          #       "guihua.ts_obsolete"
          #     ];
          #   }
          # );
        };

      # WARN: this avoids the failing tests when packaging neovim plugins
      # TODO: CHECK WHEN THIS GETS FIXED IN NEOTEST AND NIXPKGS
      # https://github.com/nvim-neotest/neotest/issues/530
      # luaPackages =
      #   final.luaPackages
      #   // {
      #     neotest = prev.luaPackages.neotest.override {
      #       doCheck = false;
      #     };
      #   };
    };
  in [
    inputs.rustaceanvim.overlays.default
    inputs.tch-nvim.overlays.default
    local
  ];
  powertop-unstable = final: prev: {
    powertop-git = prev.powertop.overrideAttrs (oldAttrs: {
      version = "2.15-pre";
      src = prev.fetchFromGitHub {
        owner = "fenrus75";
        repo = oldAttrs.pname;
        rev = "9beafe3bd5e9d4c6cf2596dacdf6ab9c9be0c85e";
        hash = "sha256-hmEu8tpbk0fdRyySZJdlFMyksOJALlp8NGjonZjLzhQ=";
      };
      buildInputs =
        (oldAttrs.buildInputs or [])
        ++ [
          prev.libtraceevent
          prev.libtracefs
        ];
    });
  };
  wayland = final: prev: {
    swaylock-effects-pr =
      prev.swaylock-effects.overrideAttrs
      (oldAttrs: {
        version =
          prev.lib.strings.concatStrings [oldAttrs.version "-unstable"];
        patches =
          (oldAttrs.patches or [])
          ++ [
            ../overlays/swaylock_effects/4_disp_img_insd_ind.patch
            ../overlays/swaylock_effects/37_cairo_bilinear.patch
            ../overlays/swaylock_effects/38_red_screen_fix.patch
            ../overlays/swaylock_effects/8_change_state_strings.patch
            ../overlays/swaylock_effects/32_unlock_on_USR1_accept_input.patch
          ];
      });
    # capnnproto-rust = prev.callPackage ./overlays/capnproto-rust {};
    electron-mail-latest =
      prev.callPackage ../pkgs/electron-mail {};
    # inherit (inputs.slh.legacyPackages.${prev.stdenv.hostPlatform.system}) systemd-lock-handler;
    # inherit (inputs.git-oxide.legacyPackages.${prev.stdenv.hostPlatform.system}) gitoxide;
    swaylockCheck =
      prev.callPackage ../pkgs/swaylock-check {inherit prev;};
    # charles = import ./pkgs/charles;

    # strace = prev.strace.overrideAttrs (old: {
    #       patches = (old.patches or []) ++ [
    #         (prev.fetchpatch {
    #            url = "https://github.com/ideak/strace/commit/cflags-decode.patch";
    #            hash = "sha256-OY1vmO4wuxWVl14o7gD5QOcmKJblyZiuzzxQMhBBThQ=";
    #          })
    #       ];
    #     });

    nw = let
      nw = inputs.nixpkgs-wayland.packages.${prev.stdenv.hostPlatform.system};

      # _swayfx = inputs.swayfx.packages.${prev.stdenv.hostPlatform.system}.swayfx-unwrapped-git.overrideAttrs (old: {

      #   src = pkgs.fetchFromGitHub {
      #     owner = "WillPower3309";
      #     repo = "swayfx";
      #     rev = "1710f7ddffbd994722f679fba8674c1919588b78";
      #     # tag = version;
      #     hash = "sha256-gdab7zkjp/S7YVCP1t/OfOdUXZRwNvNSuRFGWEJScF8=";
      #   };
      # });
      # swayfx = inputs.swayfx.packages.${prev.stdenv.hostPlatform.system}.default;
      _scenefx = inputs.scenefx.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        buildInputs = with prev; [
          libdrm
          libxkbcommon
          pixman
          libGL # egl
          mesa # gbm
          (prev.wayland.dev) # wayland-server
          wayland-protocols
          wlroots_0_18
          libgbm
          xorg.libxcb
          xorg.xcbutilwm
          cmake
        ];
      });
      _swayfx-unwrapped = prev.swayfx-unwrapped.overrideAttrs (old: {
        version = "0.5.1";
        src = prev.fetchFromGitHub {
          owner = "WillPower3309";
          repo = "swayfx";
          rev = "1710f7ddffbd994722f679fba8674c1919588b78";
          hash = "sha256-vhlRveQ1/z4ZjKHU0NjbeUdMgwt3hiTiCAgMX97IgOc=";
          # tag = version;
          # hash = "sha256-gdab7zkjp/S7YVCP1t/OfOdUXZRwNvNSuRFGWEJScF8=";
        };
        nativeBuildInputs = old.nativeBuildInputs ++ [prev.cmake];
        buildInputs = with prev;
          [
            cairo
            gdk-pixbuf
            json_c
            libdrm
            libevdev
            libGL
            libinput
            librsvg
            libxkbcommon
            pango
            pcre2
            # scenefx
            _scenefx

            (prev.wayland.dev)
            wayland-protocols
          ]
          ++ (with prev.xorg; [xcbutilwm])
          ++ (with prev; [
            (wlroots_0_18.override {enableXWayland = true;})
          ]); # buildInputs = (old.buildInputs or []) ++ (with prev; [cmake]);
        buildNativeInputs = (old.buildInputs or []) ++ (with prev; [cmake ninja _scenefx]);
      });
      swayfx-unwrapped = inputs.swayfx.packages.${prev.stdenv.hostPlatform.system}.swayfx-unwrapped-git.overrideAttrs (old: {
        # (_swayfx-unwrapped.override {
        #   scenefx = _scenefx;
        #   # wlroots_0_18 = prev.wlroots_0_19;
        # }).overrideAttrs (old: {
        postPatch = ''
          mv sway.desktop swayfx.desktop
          substituteInPlace swayfx.desktop \
          --replace-fail \
            "Exec=sway" \
            "Exec=swayfx" \
          --replace-fail \
            "Name=Sway" \
            "Name=Swayfx" \
          # --replace-fail \
          #   "DesktopNames=sway;wlroots;swayfx" \
          #   "DesktopNames=swayfx;scenefx"

          substituteInPlace meson.build \
          --replace-fail \
            "	'sway.desktop'," \
            "	'swayfx.desktop',"
        '';
        postInstall = ''
          mv $out/bin/sway $out/bin/swayfx
        '';
        meta.mainProgram = "swayfx";
      });
    in
      nw
      // {
        inherit swayfx-unwrapped;
        sway = prev.sway.override {inherit (nw) sway-unwrapped;};

        # {
        #   "url": "https://gitlab.freedesktop.org/wlroots/wlroots",
        #   "rev": "3f2aced8c6fd00b0b71da24c790850af2004052b",
        #   "date": "2023-12-21T19:42:26+01:00",
        #   "path": "/nix/store/kc7y95z65a9gzm72x8dafgm40sgidp43-wlroots",
        #   "sha256": "1hj4gq5vx8in65622yvjm8bwqkw2vpc556k9my997a0hn0ricj37",
        #   "hash": "sha256-Z0gWM7AQqJOSr2maUtjdgk/MF6pyeyFMMTaivgt+RMI=",
        #   "fetchLFS": false,
        #   "fetchSubmodules": false,
        #   "deepClone": false,
        #   "leaveDotGit": false
        # }

        # sway-beta = prev.stable.sway.override {sway-unwrapped = prev.stable.sway-unwrapped.override {wlroots = prev.wlroots_0_16.override { inherit (prev) mesa;} ;};};
        # sway-beta = prev.sway.override {
        #   sway-unwrapped =
        #     # (inputs.nixpkgs-wayland.packages.${prev.stdenv.hostPlatform.system}.sway-unwrapped.override {
        #     #   wlroots_0_16 = let
        #     #     # NOTE: use lastest "stable" wlroots
        #     #     wlroots = pkgs.wlroots_0_16.overrideAttrs (
        #     #       old: {
        #     #         src = pkgs.fetchFromGitLab {
        #     #           domain = "gitlab.freedesktop.org";
        #     #           owner = "wlroots";
        #     #           repo = "wlroots";
        #     #           hash = "sha256-JeDDYinio14BOl6CbzAPnJDOnrk4vgGNMN++rcy2ItQ=";
        #     #           rev = "0a32b5a74db06a27bee55a47205951bb277a9657";
        #     #         };
        #     #       }
        #     #     );
        #     #   in
        #     #     wlroots;
        #     #   # wlroots_0_16 = nw.wlroots;
        #     # })
        #     (pkgs.sway-unwrapped)
        #     # NOTE: using sway 1.9 branch
        #     # .overrideAttrs (old: {
        #     #   src = pkgs.fetchFromGitHub {
        #     #     owner = "swaywm";
        #     #     repo = "sway";
        #     #     rev = "68d620a8fd70d70eb91c58dcfafc4af16c58379d";
        #     #     hash = "sha256-WxnT+le9vneQLFPz2KoBduOI+zfZPhn1fKlaqbPL6/g=";
        #     #   };
        #     # });
        #     ;
        # };

        # swayfx = prev.swayfx.override {
        #   swayfx-unwrapped =
        #     # install_data(
        #     # 	'sway.desktop',
        #     # 	install_dir: join_paths(datadir, 'wayland-sessions')
        #     # )
        #     #           then ''
        #     #   substituteInPlace src/commands/cynthion_setup.py \
        #     #   --replace-fail \
        #     #         "        _install_udev(args)" \
        #     #         "        logging.info(\"✅ NixOS has already took care of setup process.\n   Please verify with cythion setup --check\")"
        #     # ''
        #     prev.swayfx-unwrapped.overrideAttrs (old: {
        #       postPatch = ''
        #         mv sway.desktop swayfx.desktop
        #         substituteInPlace meson.build \
        #         --replace-fail \
        #           "	'sway.desktop'," \
        #           "	'swayfx.desktop',"
        #       '';
        #       # postInstall = ''
        #       #
        #       #
        #       # '';
        #     });
        # };
        # NOTE: sway from nixpkgs-wayland currently is not operational
        # (spotify black screens even in xwayland, firefox has weird scaling issues moving from screen to screen.)
        # for now use sway from nixpkgs.
        # sway-beta = prev.swayfx;
        # hypr = ((import (hyprland-patched + "/flake.nix")).outputs{ inherit nixpkgs;}).packages.${prev.stdenv.hostPlatform.system};
        # NOTE: sway from nixpkgs-wayland currently is not operational
        # (spotify black screens even in xwayland, firefox has weird scaling issues moving from screen to screen.)
        # for now use sway from nixpkgs.
        sway-beta = prev.sway.override {inherit (nw) sway-unwrapped;};
        swayidle-test = nw.swayidle.override {systemdSupport = false;};
        # sway-beta = pkgs.swayfx;
        # hypr = ((import (hyprland-patched + "/flake.nix")).outputs{ inherit nixpkgs;}).packages.${prev.stdenv.hostPlatform.system};
        # zen-browser = inputs.zen-browser.packages.${prev.stdenv.hostPlatform.system}.default;
        swayfx = prev.swayfx.override {inherit swayfx-unwrapped;};
      };
  };
  firefox = final: prev: {
    # NOTE: This the best way think of manually updating firefox
    # TODO: (med prio) break this off into its own flake. This will allow for
    # auto-update per-flake basis, and maybe run checks?
  };
  figma-linux = final: prev: {
    figma-linux = prev.figma-linux.overrideAttrs (old: rec {
      version = "0.11.4";
      src = prev.fetchurl {
        url = "https://github.com/Figma-Linux/figma-linux/releases/download/v${version}/figma-linux_${version}_linux_amd64.deb";
        hash = "sha256-ukUsNgWOtIRe54vsmRdI62syjIPwSsgNV7kITCw0YUQ=";
      };
      # runtimeDependenciesPath = (old.runtimeDependenciesPath or []) ++ (lib.makeLibraryPath [ prev.libGL]);
      preFixup = ''
         gappsWrapperArgs+=(
          --prefix LD_LIBRARY_PATH : ${prev.lib.makeLibraryPath [prev.libGL]}
        )
      '';
    });
  };
  ncspot = final: prev: {
    ncspot = (prev.ncspot.overrideAttrs
      (old: rec {
        version = "1.3.3";
        src = prev.fetchFromGitHub {
          owner = "MichaelPachec0";
          inherit (old.src) repo;
          # rev = "0b6400e7d5d86460cdaaff39be4585edd1f4d628";
          # hash = "sha256-mGv2FNTHp25/ZFSpAiU7hA41VrXWO35AKFUther56Qo=";
          # rev = "f6b65b9b53fd7397e17ff094efad0384e6ff6250";
          # hash = "sha256-CpcB+/z47r+XorBS16yYjVESX7L+vJQnsw7v0N4R2ok=";
          # rev = "f6d9af30637403559a72ba343c28c239fbad0640";
          # hash = "sha256-S8EWp9vtWDnTDzfDz45LvbRfOS4yfIeKdIstpPQxsHc=";
          # rev = "3a7a0adfb7af7b00a1e335da1015e1ea5d789f88";
          # hash = "sha256-4lXdGqsKSnJGwJJQ4jKUdCS11ZSJxZL1786C+aoY/xk=";
          rev = "c3decd3bf22f31b8e12223f5182dfc78e6862b6d";
          hash = "sha256-fyKBpyE/TjwPo8nZCPxjBmHwHhsNVhIDtPwt3e6toEs=";
        };

        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          name = "${old.pname}-${old.version}";
          inherit src;
          # when rebuilding make sure to make hash = "" so that the cargo hash gets computed
          # hash = "sha256-1+dt7tzYpV5g/rlI3Xyv7X5BdyiheOZNO122H8eKA2E=";
          # hash = "sha256-Qjsn3U9KZr5qZliJ/vbudfkH1uOng1N5c8dAyH+Y5vQ=";
          # hash = "sha256-ivlanIexJDn2V47ni0cCLCsNC+ObMh/5IpvPXuv+1/Q=";
          # hash = "sha256-FepaUgwOaQKW+0ugGDbqFmZmVPL7wqVaYyLk5UjND2o=";
          # hash = "sha256-XmEiTUKb7ksPxQbjjDG8hZmIM/vJ6nnb30GSJp9F+18=";
          hash = "sha256-ny1vGZSUHxjUZb/nxu2SXP1gimPlPBUejAjiqPpe+CM=";
        };
        passthru = {
          tests.version = old.testers.testVersion {package = final.ncspot;};
          updateScript = old.nix-update-script {};
        };
        # cargoBuildFlags = ["--features=cover"];
      }))
    .override {withCover = true;};

    # fastanime = inputs.fastanime.packages.${pkgs.system}.default;
  };
  fastanime = final: prev: {
    fastanime = inputs.fastanime.packages.${prev.stdenv.hostPlatform.system}.default;
  };

  pam_rssh = final: prev: {
    pam_rssh = prev.callPackage ../overlays/pam_rssh {};
  };
  # pam_rssh = final: prev: {
  #   pam_rssh =
  #     prev.pam_rssh.overrideAttrs
  #     (old: rec {
  #       version = "master_1.2.0_6-22-25";
  #       src = prev.fetchFromGitHub {
  #         inherit (old.src) owner repo;
  #         rev = "98ab0f80d116923eae196a496e01b2975be9eeeb";
  #         hash = "sha256-DCCBIjo6h3E+fyk2vN2EAQP+G+IGWWxI7FYJzC9yRgQ=";
  #         fetchSubmodules = true;
  #         deepClone = true;
  #       };
  #       cargoDeps = prev.rustPlatform.importCargoLock {
  #         lockFile = "${src}/Cargo.lock";
  #       };
  #       # useFetchCargoVendor = true;
  #       # cargoHash = "sha256-4DoMRtyT2t4degi8oOyVTStb0AU0P/7XeYk15JLRrqg=";
  #       # cargoDeps = prev.rustPlatform.fetchCargoVendor {
  #       #   name = "${old.pname}-${old.version}";
  #       #   inherit src;
  #       #   hash = "sha256-4DoMRtyT2t4degi8oOyVTStb0AU0P/7XeYk15JLRrqg=";
  #       #   fetchSubmodules = true;
  #       # };
  #     });
  # };
  latest = final: prev: let
    sway = final.nw.sway-beta;
    hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.default;
    # waybar = prev.waybar.override {inherit sway hyprland;};
    waybar = prev.waybar;
  in {
    latest.sway = prev.sway.override {inherit (final.nw) sway-unwrapped;};
    latest.hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.default;
    latest.waybar = waybar;
    latest.firefox-devedition-bin = inputs.firefox.packages.${prev.stdenv.hostPlatform.system}.firefox-devedition-bin.override {
      extraPolicies = {
        DisableTelemetry = true;
      };
    };
  };
  baseDesktop = [
    inputs.nix-vscode-extensions.overlays.default
    # inputs.swayfx.overlays.default
    # inputs.waybar-git.overlays.default
    inputs.nix-your-shell.overlays.default
    inputs.rust-overlay.overlays.default
    # inputs.hyprland.overlays.default
    # (import ./pkgs/charles)
    firefox
    wayland
    figma-linux
    ncspot
    fastanime
    # NOTE: still need to migrate from using this, as sg has now moved from using an overlay.
    # inputs.sg.overlays.default
  ];
  # TODO: decide if abstracting this is worthwhile.
  overlayList = {};
  mkOverlay = {channel ? ""}: let
    overlays = ["base" "nixosMinimal" "nixosDesktop" "homeManagerMinmal" "homeManagerDesktop"];
  in
    builtins.map (o: {
      name = o;
      value = overlayList."${o}";
    })
    overlays;
  base = [
    channels
    inputs.joshuto.overlays.default
    inputs.flake-playground.overlays.default
    # (
    #   final: prev: {
    #     joshuto = prev.joshuto.override {rustPlatform = prev.unstable.rustPlatform;};
    #   }
    # )
    pam_rssh
    # modules
  ];
in {
  # stable = mkOverlay "stable";
  # unstable = mkOverlay;
  stable = let
    # NOTE: for some reason this does not work, its asking for config, where it should not be asking for it
    # this is not an issue when home-manager is defined in flake.nix.
    # TODO: (high prio) understand why this is the case. Its is not apparent why this is an issue.
    hm =
      inputs.home-manager-stable.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
      };
  in {
    # Stable-channel counterpart of unstable.hmIntegrationOverlays (see below);
    # only hoisted for stable *desktop* hosts. Servers (kore) set desktop = false
    # and never force this.
    hmIntegrationOverlays =
      vimPluginsOverlayList
      ++ lspServers
      ++ [inputs.claude-code.overlays.default];
    # base =
    # mkOverlayModules base
    # ++ inputs.sops-nix.nixosModules.sops;
    nixosServer = [
      (mkOverlayModules
        (base
          ++ [
            # NOTE: this is needed since powertop has extra fixes for stable.
            powertop-unstable
          ]))
    ];
    nixosDesktop = [
      (mkOverlayModules (
        base
        ++ baseDesktop
      ))
    ];
    homeManager = hm;
    homeManagerMinmal = mkOverlayModules base;
    homeManagerDesktop =
      [
        (mkOverlayModules
          (
            base
            ++ baseDesktop
            ++ vimPluginsOverlayList
            ++ [
              powertop-unstable
              # TODO: neovim nightly has changed how neotest works.
              # ...ry.nvim-scm-1-unstable-scm-1/lua/luassert/assertions.lua:115: the 'equals' function requires a minimum of 2 arguments, got: 1.3
              # switching over to stable neovim
              #
              # inputs.neovim.overlays.default
              powertop-unstable
              inputs.nix-vscode-extensions.overlays.default
            ]
            ++ lspServers
          ))
      ];
  };
  unstable = let
    hm = inputs.home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    };
  in {
    # Overlays the home-manager desktop config needs that the NixOS desktop config
    # does not apply on its own. With useGlobalPkgs = true the integrated home
    # config reuses the system pkgs, so features/nixos/home hoists these up.
    hmIntegrationOverlays =
      vimPluginsOverlayList
      ++ lspServers
      ++ [inputs.claude-code.overlays.default];
    nixosServer = mkOverlayModules (base
      ++ [
        powertop-unstable
      ]);
    nixosDesktop =
      [
        (mkOverlayModules
          (
            base
            ++ baseDesktop
            ++ [
              powertop-unstable
              latest
              inputs.nix-your-shell.overlays.default
              # inputs.neovim.overlays.default
            ]
          ))
      ]
      ++ [
        inputs.sops-nix.nixosModules.sops
        # WARN: this needs to be either idsabled on first install or the segger
        #  software needs to be added in manually by sshing and nix-store -ing it
        # inputs.jlink.nixosModule
      ];
    homeManagerModule = hm;
    homeManagerMinmal = mkOverlayModules base;
    homeManagerDesktop =
      [
        (mkOverlayModules
          (
            base
            ++ baseDesktop
            ++ vimPluginsOverlayList
            ++ [
              powertop-unstable
              latest
              # inputs.neovim.overlays.default
              powertop-unstable
              inputs.nix-vscode-extensions.overlays.default
            ]
            ++ lspServers
          ))
      ];
    # nixosDesktop =
  };
  # nixosMinimal = nixos;
  # nixosDesktop = nixosDesktop;
  # homeManagerModules = homeManagerModules;
  # homeManagerMinmal = homeManagerMinmal;
  # base = base;
  # channels = channels;
  # base =
}
#
# overlayModule = [
#   ({
#     config,
#     pkgs,
#     lib,
#     ...
#   }: {
#     nixpkgs.overlays = [
#       (final: prev: {
#         stable = prepNixpkgs inputs.nixpkgs-stable prev.stdenv.hostPlatform.system;
#         master = prepNixpkgs inputs.nixpkgs-master prev.stdenv.hostPlatform.system;
#         legacy = prepNixpkgs inputs.nixpkgs-oldstable prev.stdenv.hostPlatform.system;
#         unstable = prepNixpkgs inputs.nixpkgs-unstable-small prev.stdenv.hostPlatform.system;
#       })
#     ];
#   })
# ];
# # TODO: (low prio) refactor this to its own file.
# baseModules = [
#   ({
#     config,
#     pkgs,
#     lib,
#     # inputs,
#     ...
#   }: let
#     # waybar-git = inputs.
#   in {
#     nixpkgs.overlays = [
#       inputs.nixd.overlays.default
#       # dont use upstream, use stable
#       # inputs.sg.overlays.default
#       inputs.nixneovim.overlays.default
#       inputs.nix-vscode-extensions.overlays.default
#       inputs.nixneovimplugins.overlays.default
#       inputs.swayfx.overlays.default
#       inputs.tch-nvim.overlays.default
#       inputs.nix-your-shell.overlays.default
#
#       # inputs.waybar-git.overlays.default
#       # inputs.waybar-test.overlays.default
#       inputs.rustaceanvim.overlays.default
#       # inputs.neovim.overlays.default
#       inputs.hyprland.overlays.default
#       # # WARN: for some reason the upstream overlay gives me a
#       # (final: prev: {
#       #   waybar = inputs.waybar-test.packages.${prev.stdenv.hostPlatform.system}.default;
#       # })
#       # streamlink stuff
#       # ./lib/python3.12/site-packages/streamlink/plugins/twitch.py
#       (final: prev: let
#         sway = final.nw.sway-beta;
#         hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.default;
#         waybar = pkgs.waybar.override {inherit sway hyprland;};
#       in {
#         sway = prev.sway.override {inherit (final.nw) sway-unwrapped;};
#         latest.sway = sway;
#         latest.waybar = inputs.waybar-git.packages.${prev.stdenv.hostPlatform.system}.default.override {inherit waybar;};
#         # NOTE: This the best way think of manually updating firefox
#         # TODO: (med prio) break this off into its own flake. This will allow for
#         # auto-update per-flake basis, and maybe run checks?
#         latest.firefox-devedition-bin = let
#           # NOTE: find a better way of doing this. Currently the way to get the hash is to change version
#           # to the updated one and then wait for failure to show the new hash.
#           # version = "131.0b9";
#           # sha256 = "1rfjj77sbwn563hwdd7njf4bkaqmrz9rffpi83fa63mdb6dqfnr1";
#           version = "134.0b9";
#           sha256 = "1rvciz3shnki9mdb3794m2kksa747imya228wn4k5mlyg91aa5gc";
#           url = "https://archive.mozilla.org/pub/devedition/releases/${version}/linux-x86_64/en-US/firefox-${version}.tar.bz2";
#         in
#           prev.wrapFirefox (prev.firefox-devedition-bin-unwrapped.overrideAttrs (old: {
#             inherit version;
#             # NOTE: does this needs to have the builtins namespace? this should be already namespaced as i understood.
#             src = builtins.fetchurl {inherit url sha256;};
#           })) {
#             extraPolicies = {
#               DisableTelemetry = true;
#             };
#           };
#         # nyxt = prev.nyxt.override { sbclPackages = prev.sbcl_2_4_6.pkgs;};
#       })
#       (final: prev: {
#         # TODO: convert to vimPlugins.extend
#         # format is (final': prev': {
#         #   ...plugins to add/modify...
#         #   })
#         vimPlugins =
#           prev.vimPlugins
#           // {
#             # TODO: (low prio) convert import to callPackage
#             vimBeGood =
#               import ./pkgs/vimPlugins/vim-be-good {inherit pkgs;};
#             coc-lightbulb =
#               import ./pkgs/vimPlugins/coc-lightbulb {inherit pkgs;};
#             coc-elixir =
#               import ./pkgs/vimPlugins/coc-elixir {inherit pkgs;};
#             stay-centered =
#               import ./pkgs/vimPlugins/stay-centered {inherit pkgs;};
#             block-nvim =
#               import ./pkgs/vimPlugins/block-nvim {inherit pkgs;};
#             indentmini =
#               import ./pkgs/vimPlugins/indentmini {inherit pkgs;};
#             virt-column =
#               import ./pkgs/vimPlugins/virt-column {inherit pkgs;};
#             wtf-nvim =
#               import ./pkgs/vimPlugins/wtf-nvim {inherit pkgs;};
#             nvim-dap-repl-highlights =
#               import ./pkgs/vimPlugins/nvim-dap-repl-highlights {inherit pkgs;};
#             neoai-nvim =
#               import ./pkgs/vimPlugins/neoai {inherit pkgs;};
#             osv-nvim =
#               import ./pkgs/vimPlugins/ossfv {inherit pkgs;};
#             neotest-gtest = pkgs.callPackage ./pkgs/vimPlugins/neotest-gtest {};
#             telescope-docker-nvim = pkgs.callPackage ./pkgs/vimPlugins/telescope-docker {};
#             nvim-emmet = pkgs.callPackage ./pkgs/vimPlugins/nvim-emmet {};
#             fermyon-spin = pkgs.callPackage ./pkgs/fermyon-spin;
#             git-nvim = pkgs.callPackage ./pkgs/vimPlugins/git-nvim {};
#             ts-software-licenses-nvim = pkgs.callPackage ./pkgs/vimPlugins/ts-software-license {};
#             kitty-scrollback-nvim = pkgs.callPackage ./pkgs/vimPlugins/kitty-scrollback {};
#             fidget-nvim = prev.vimPlugins.fidget-nvim.overrideAttrs (old: {
#               version = "2025-01-08-master";
#               src = pkgs.fetchFromGitHub {
#                 owner = "j-hui";
#                 repo = "fidget.nvim";
#                 rev = "a0abbf18084b77d28bc70e24752e4f4fd54aea17";
#                 hash = "sha256-o0za2NxFtzHZa7PRIm9U/P1/fwJrxS1G79ukdGLhJ4Q=";
#               };
#             });
#             clear-action-nvim = pkgs.callPackage ./pkgs/vimPlugins/clear-action-nvim {};
#             # none-ls-nvim = pkgs.callPackage ./pkgs/vimPlugins/none-ls-nvim {};
#             inlay-hints-nvim = pkgs.callPackage ./pkgs/vimPlugins/inlay-hints {};
#             guihua-lua = pkgs.callPackage ./pkgs/vimPlugins/guihua-lua {};
#             pfp-vim = pkgs.callPackage ./pkgs/vimPlugins/pfp-vim {};
#             # sg-nvim =  inputs.sg.packages.${prev.stdenv.hostPlatform.system}.default;
#             # inherit (inputs.sg.packages.${prev.stdenv.hostPlatform.system}) sg-nvim;
#             # inherit (inputs.git-oxide.legacyPackages.${prev.stdenv.hostPlatform.system}) gitoxide;
#             cspell-nvim = pkgs.callPackage ./pkgs/vimPlugins/cspell-nvim {};
#             none-ls-extras-nvim = pkgs.callPackage ./pkgs/vimPlugins/none-ls-extras-nvim {};
#           };
#         emmet-language-server = pkgs.callPackage ./pkgs/emmet-ls {};
#         # onthespot = pkgs.callPackage ./pkgs/onthespot {};
#
#         swaylockCheck =
#           prev.callPackage ./pkgs/swaylock-check {inherit pkgs;};
#         powertop-git = prev.powertop.overrideAttrs (oldAttrs: {
#           version = "2.15-pre";
#           src = prev.fetchFromGitHub {
#             owner = "fenrus75";
#             repo = oldAttrs.pname;
#             rev = "9beafe3bd5e9d4c6cf2596dacdf6ab9c9be0c85e";
#             hash = "sha256-hmEu8tpbk0fdRyySZJdlFMyksOJALlp8NGjonZjLzhQ=";
#           };
#           buildInputs =
#             (oldAttrs.buildInputs or [])
#             ++ [
#               prev.libtraceevent
#               prev.libtracefs
#               prev.zlib
#             ];
#         });
#         swaylock-effects-pr =
#           pkgs.swaylock-effects.overrideAttrs
#           (oldAttrs: {
#             version =
#               lib.strings.concatStrings [oldAttrs.version "-unstable"];
#             patches =
#               (oldAttrs.patches or [])
#               ++ [
#                 ./overlays/swaylock_effects/4_disp_img_insd_ind.patch
#                 ./overlays/swaylock_effects/37_cairo_bilinear.patch
#                 ./overlays/swaylock_effects/38_red_screen_fix.patch
#                 ./overlays/swaylock_effects/8_change_state_strings.patch
#                 ./overlays/swaylock_effects/32_unlock_on_USR1_accept_input.patch
#               ];
#           });
#         # capnnproto-rust = prev.callPackage ./overlays/capnproto-rust {};
#         electron-mail-latest =
#           prev.callPackage ./pkgs/electron-mail {};
#         # inherit (inputs.slh.legacyPackages.${prev.stdenv.hostPlatform.system}) systemd-lock-handler;
#         # inherit (inputs.git-oxide.legacyPackages.${prev.stdenv.hostPlatform.system}) gitoxide;
#         # charles = import ./pkgs/charles;
#
#         # strace = prev.strace.overrideAttrs (old: {
#         #       patches = (old.patches or []) ++ [
#         #         (prev.fetchpatch {
#         #            url = "https://github.com/ideak/strace/commit/cflags-decode.patch";
#         #            hash = "sha256-OY1vmO4wuxWVl14o7gD5QOcmKJblyZiuzzxQMhBBThQ=";
#         #          })
#         #       ];
#         #     });
#
#         nw = let
#           nw = inputs.nixpkgs-wayland.packages.${prev.stdenv.hostPlatform.system};
#         in
#           nw
#           // {
#             # sway = prev.sway.override {inherit (nw) sway-unwrapped;};
#
#             # {
#             #   "url": "https://gitlab.freedesktop.org/wlroots/wlroots",
#             #   "rev": "3f2aced8c6fd00b0b71da24c790850af2004052b",
#             #   "date": "2023-12-21T19:42:26+01:00",
#             #   "path": "/nix/store/kc7y95z65a9gzm72x8dafgm40sgidp43-wlroots",
#             #   "sha256": "1hj4gq5vx8in65622yvjm8bwqkw2vpc556k9my997a0hn0ricj37",
#             #   "hash": "sha256-Z0gWM7AQqJOSr2maUtjdgk/MF6pyeyFMMTaivgt+RMI=",
#             #   "fetchLFS": false,
#             #   "fetchSubmodules": false,
#             #   "deepClone": false,
#             #   "leaveDotGit": false
#             # }
#
#             # sway-beta = prev.stable.sway.override {sway-unwrapped = prev.stable.sway-unwrapped.override {wlroots = prev.wlroots_0_16.override { inherit (prev) mesa;} ;};};
#             # sway-beta = prev.sway.override {
#             #   sway-unwrapped =
#             #     # (inputs.nixpkgs-wayland.packages.${prev.stdenv.hostPlatform.system}.sway-unwrapped.override {
#             #     #   wlroots_0_16 = let
#             #     #     # NOTE: use lastest "stable" wlroots
#             #     #     wlroots = pkgs.wlroots_0_16.overrideAttrs (
#             #     #       old: {
#             #     #         src = pkgs.fetchFromGitLab {
#             #     #           domain = "gitlab.freedesktop.org";
#             #     #           owner = "wlroots";
#             #     #           repo = "wlroots";
#             #     #           hash = "sha256-JeDDYinio14BOl6CbzAPnJDOnrk4vgGNMN++rcy2ItQ=";
#             #     #           rev = "0a32b5a74db06a27bee55a47205951bb277a9657";
#             #     #         };
#             #     #       }
#             #     #     );
#             #     #   in
#             #     #     wlroots;
#             #     #   # wlroots_0_16 = nw.wlroots;
#             #     # })
#             #     (pkgs.sway-unwrapped)
#             #     # NOTE: using sway 1.9 branch
#             #     # .overrideAttrs (old: {
#             #     #   src = pkgs.fetchFromGitHub {
#             #     #     owner = "swaywm";
#             #     #     repo = "sway";
#             #     #     rev = "68d620a8fd70d70eb91c58dcfafc4af16c58379d";
#             #     #     hash = "sha256-WxnT+le9vneQLFPz2KoBduOI+zfZPhn1fKlaqbPL6/g=";
#             #     #   };
#             #     # });
#             #     ;
#             # };
#             # swayfx = prev.sway.override {
#             #   sway-unwrapped = prev.swayfx-unwrapped;
#             # };
#             # NOTE: sway from nixpkgs-wayland currently is not operational
#             # (spotify black screens even in xwayland, firefox has weird scaling issues moving from screen to screen.)
#             # for now use sway from nixpkgs.
#             sway-beta = prev.sway.override {inherit (nw) sway-unwrapped;};
#             swayidle-test = nw.swayidle.override {systemdSupport = false;};
#             # sway-beta = pkgs.swayfx;
#             # hypr = ((import (hyprland-patched + "/flake.nix")).outputs{ inherit nixpkgs;}).packages.${prev.stdenv.hostPlatform.system};
#             zen-browser = inputs.zen-browser.packages.${pkgs.system}.default;
#           };
#         autotools-language-server = pkgs.callPackage ./pkgs/autotools-ls {};
#         figma-linux = prev.figma-linux.overrideAttrs (old: rec {
#           version = "0.11.4";
#           src = prev.fetchurl {
#             url = "https://github.com/Figma-Linux/figma-linux/releases/download/v${version}/figma-linux_${version}_linux_amd64.deb";
#             hash = "sha256-ukUsNgWOtIRe54vsmRdI62syjIPwSsgNV7kITCw0YUQ=";
#           };
#           # runtimeDependenciesPath = (old.runtimeDependenciesPath or []) ++ (lib.makeLibraryPath [ prev.libGL]);
#           preFixup = ''
#              gappsWrapperArgs+=(
#               --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [prev.libGL]}
#             )
#           '';
#         });
#         ncspot = (prev.ncspot.overrideAttrs
#           (old: rec {
#             src = prev.fetchFromGitHub {
#               owner = "MichaelPachec0";
#               inherit (old.src) repo;
#               # rev = "0b6400e7d5d86460cdaaff39be4585edd1f4d628";
#               # hash = "sha256-mGv2FNTHp25/ZFSpAiU7hA41VrXWO35AKFUther56Qo=";
#               rev = "f6b65b9b53fd7397e17ff094efad0384e6ff6250";
#               hash = "sha256-CpcB+/z47r+XorBS16yYjVESX7L+vJQnsw7v0N4R2ok=";
#             };
#
#             # REMINDER: when changes are needed, this needs to be set to lib.fakeHash
#             cargoDeps = old.cargoDeps.overrideAttrs (prev.lib.const {
#               name = "${old.pname}-vendor.tar.gz";
#               inherit src;
#               outputHash = "sha256-yHgj85VylhE2S/Fyu3wBdxdmNIvzT9D1dPCYXoVf6oc=";
#               # cargoSha256 = lib.fakeHash;
#               outputHashMode = "recursive";
#             });
#             # cargoBuildFlags = ["--features=cover"];
#           }))
#         .override {withCover = true;};
#         # xdg-desktop-portal-wlr = prev.emptyDirectory;
#         # xdg-desktop-portal-hyprland = prev.xdg-desktop-portal-hyprland.overrideAttrs (old: {
#         #   postInstall = ''
#         #     wrapProgramShell $out/bin/hyprland-share-picker \
#         #       "''${qtWrapperArgs[@]}" \
#         #       --prefix PATH ":" ${lib.makeBinPath [prev.slurp prev.hyprland]}
#         #
#         #     wrapProgramShell $out/libexec/xdg-desktop-portal-hyprland \
#         #       --prefix PATH ":" ${lib.makeBinPath [(placeholder "out")]}
#         #     # hyprland xdg keep getting enabled with sway. this makes it so that it only starts when hyprland does.
#         #     sed -i 's/^UseIn=.*$/UseIn=Hyprland;/' $out/share/xdg-desktop-portal/portals/hyprland.portal
#         #   '';
#         # });
#
#         fastanime = inputs.fastanime.packages.${pkgs.system}.default;
#       })
#     ];
#   })
# ];
# nixosModules =
#   baseModules
#   ++ [
#     inputs.nixneovim.nixosModules.nixos
#     home-manager.nixosModules.home-manager
#     {
#       home-manager.useGlobalPkgs = true;
#       home-manager.useUserPackages = true;
#     }
#   ];
# homeManagerModules =
#   baseModules
#   ++ [inputs.nixneovim.nixosModules.homeManager];
# overlays = import ./helpers/overlays.nix {inherit inputs;};
# # externalModules = import ./helpers/externalModules.nix {inherit inputs;};
# # home-manager-stable = [
# #   inputs.home-manager-stable.nixosModules.home-manager
# #   {
# #     home-manager.useGlobalPkgs = true;
# #     home-manager.useUserPackages = true;
# #   }
# # ];
# # home-manager-unstable =
# #   inputs.home-manager.nixosModules.home-manager
# #   {
# #     home-manager.useGlobalPkgs = true;
# #     home-manager.useUserPackages = true;
# #   };

