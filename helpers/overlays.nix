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
      # The custom vim plugins now live in flake-playground and are injected via
      # inputs.flake-playground.overlays.vimPlugins (added to the list below).
      # Only the two non-moved overrides remain here.
      vimPlugins =
        prev.vimPlugins
        // {
          # fermyon-spin is a CLI tool historically parked in the vimPlugins
          # namespace, not a neovim plugin, so it stayed behind.
          fermyon-spin = prev.callPackage ../pkgs/fermyon-spin;
          # fidget-nvim is pinned to an older rev for compatibility; it's an
          # override of the nixpkgs plugin (not a packaged dir), so not moved.
          fidget-nvim = prev.vimPlugins.fidget-nvim.overrideAttrs (old: {
            version = "2024-02-13-master";
            src = prev.fetchFromGitHub {
              owner = "j-hui";
              repo = "fidget.nvim";
              rev = "60404ba67044c6ab01894dd5bf77bd64ea5e09aa";
              hash = "sha256-cfoz2nGX7yzDLjTitposErJpC8EVX0DBy69kFKY0jps=";
            };
          });
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
    # custom vim plugins (nvfetcher-tracked), moved out of ../pkgs/vimPlugins.
    inputs.flake-playground.overlays.vimPlugins
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
    electron-mail-latest =
      prev.callPackage ../pkgs/electron-mail {};
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
      swayfx-unwrapped = prev.swayfx-unwrapped.overrideAttrs (old: {
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

        sway-beta = prev.sway.override {inherit (nw) sway-unwrapped;};
        swayidle-test = nw.swayidle.override {systemdSupport = false;};
        swayfx = prev.swayfx.override {inherit swayfx-unwrapped;};
      };
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

  pam_rssh = final: prev: {
    pam_rssh = prev.callPackage ../overlays/pam_rssh {};
  };
  latest = final: prev: {
    # Hyprland CORE: bumped to the v0.56.1 point release and carrying the two
    # crash patches. Overrides the TOP-LEVEL `hyprland` (not just latest.hyprland
    # below) so the compositor AND hy3 -- which builds against final.hyprland --
    # share the one binary and the plugin hash check still matches.
    #
    # nixpkgs is still on 0.56.0; we already build the compositor from source for
    # the patches, so taking the point release costs nothing extra. 0.56.1 is a
    # pure bugfix bump (28 files) and every header change in it is ADDITIVE (a
    # new signal, a method decl, an event, an enum entry) -- nothing hy3 uses is
    # removed or renamed, so the pinned hy3 needs no source change. hy3 is also
    # already at its newest tag (hl0.56.0.1 = 42b7ed8 = its master HEAD).
    hyprland = prev.hyprland.overrideAttrs (old: {
      version = "0.56.1";
      src = prev.fetchFromGitHub {
        owner = "hyprwm";
        repo = "hyprland";
        fetchSubmodules = true;
        tag = "v0.56.1";
        hash = "sha256-u3DU6wmJ2PZk8kAOnx64MTlVxp/hZH+oUtXouj1E3+0=";
      };
      # `hyprctl version` is fed from nixpkgs' pkgs/by-name/hy/hyprland/info.json,
      # which still describes 0.56.0 -- restate it for the bumped src, or crash
      # reports name a commit we are not running.
      env =
        (old.env or {})
        // {
          GIT_COMMIT_HASH = "5c9377c15f85c50648f35ca5a213754f95b93ca0";
          GIT_COMMIT_MESSAGE = "version: bump to 0.56.1";
          GIT_COMMIT_DATE = "2026-07-27";
          GIT_TAG = "v0.56.1";
        };
      patches =
        (old.patches or [])
        ++ [
          # Compositor SIGSEGV when the session locks while a grabbing xdg_popup
          # (a bar dropdown/menu) is open: newLock is emitted before m_locked is
          # set, so the grab is torn down with isSessionLocked() still false.
          # Still unfixed on main (SessionLock.cpp:198 is unchanged) and the
          # patch still applies there, so this one survives a future bump.
          # See docs/hyprland-popup-lock-crash.
          ../overlays/hyprland-popup-sessionlock-crash.patch
          # Same crash family, different site: a screencopy
          # (ext-image-copy-capture) create_frame that lands after its output
          # was removed derefs a null monitor in CScreenshareFrame::transform.
          # Hit on every resume-with-monitor-unplugged, because the lock's
          # ScreencopyView backdrop captures per Quickshell.screens entry.
          #
          # BACKPORT ONLY: main lost this crash site incidentally in 901881c9
          # ("render: always render in normal transform", #15714), which is not
          # on the 0.56.x branch. The patch therefore does NOT apply past
          # 0.56.x -- DROP it, do not rebase it, when leaving this series.
          # See docs/hyprland-screencopy-dead-output-crash.
          ../overlays/hyprland-screencopy-dead-output-crash.patch
        ];
    });
    # xdg-desktop-portal-hyprland past its v1.4.0 tag, for 71ae1a3a
    # "screencopy: don't send bad transform information over wire"
    # (ref hyprwm/hyprland#15714): the portal used to forward the output's
    # transform verbatim, so a screencast could be handed a transform that does
    # not describe the buffer it came with. It now reports NORMAL for region
    # captures, and for output captures only keeps the transform when the frame
    # dimensions are actually swapped relative to the output.
    #
    # Deliberately paired with the 0.56.1 compositor above, which PREDATES
    # #15714 and so still renders transformed buffers. The heuristic is written
    # to straddle both (its own comment: "always fall back to new... 180 will be
    # wrong on old hl"), and on non-rotated outputs -- every monitor here -- both
    # branches yield NORMAL, so the pairing is a no-op today and correct once the
    # compositor moves past 0.56.x. Revisit if a display is ever rotated.
    #
    # The portal takes `hyprland` only to put it on the share-picker's PATH, so
    # it follows the patched compositor above with no extra wiring.
    xdg-desktop-portal-hyprland = prev.xdg-desktop-portal-hyprland.overrideAttrs (old: {
      version = "1.4.0-unstable-b653ab5";
      src = prev.fetchFromGitHub {
        owner = "hyprwm";
        repo = "xdg-desktop-portal-hyprland";
        rev = "b653ab53a435e92cc00f34771e6823bc59f2f740";
        hash = "sha256-sNIGmqZJiOM/lCWUuslV53zuk/p5sGCRcS3kHKfxQvA=";
      };
      # The packaged changelog interpolates v${version} into a releases URL,
      # which does not exist for a between-tags pin.
      meta =
        (old.meta or {})
        // {
          changelog = "https://github.com/hyprwm/xdg-desktop-portal-hyprland/compare/v1.4.0...b653ab53a435e92cc00f34771e6823bc59f2f740";
        };
    });
    # Patch Quickshell: the forked PAM subprocess frees the caller's
    # `pam_response**` out-param (a stack address) on any IPC write failure, so
    # a shell that dies while a PAM child is still blocked in pam_fprintd turns
    # into a bogus "quickshell crashed" SIGSEGV report. Unfixed upstream as of
    # 28771c7. Patched at the TOP-LEVEL `quickshell` so the raw `pkgs.quickshell`
    # uses (swayidle.nix, quickshell-lock.nix) and the HM module's own
    # overrideAttrs (features/hm/wayland/quickshell.nix) all stack on the fix.
    # See docs/quickshell-pam-invalid-free.
    quickshell = prev.quickshell.overrideAttrs (old: {
      patches = (old.patches or []) ++ [../overlays/quickshell-pam-conversation-invalid-free.patch];
    });
    latest = {
      # nixpkgs ships Hyprland 0.56.0; the `hyprland` attr above bumps it to
      # v0.56.1 and carries the two crash patches. The old 0005 popup-coords
      # SIGSEGV patch is obsolete (fixed upstream in 0.56, #15416) and dropped.
      # nixpkgs' hyprlandPlugins.hy3 is still hl0.55.0, which will not load
      # against a 0.56 compositor, so hy3's src is pinned to the matching
      # hl0.56.0.1 release (see the hy3 attr below) with our patches re-applied.
      inherit (final) hyprland;
      inherit (prev) waybar;

      sway = prev.sway.override {inherit (final.nw) sway-unwrapped;};
      # nixpkgs' hy3 is hl0.55.0; pin the src to the hl0.56.0.1 release (built
      # against final.hyprland, so the plugin hash always matches whatever that
      # attr resolves to -- 0.56.1 now) and re-apply our dispatcher patches --
      # 0004 rebased onto the 0.56 workspace API (getWorkspaceByID ->
      # State::workspaceState()->query().id().run()). hl0.56.0.1 is still hy3's
      # newest tag AND its master HEAD, and 0.56.1 removes/renames nothing it
      # uses, so there is nothing to resync here for the point release.
      hy3 = (final.hyprlandPlugins.hy3.override {inherit (final) hyprland;}).overrideAttrs (old: {
        src = final.fetchFromGitHub {
          owner = "outfoxxed";
          repo = "hy3";
          rev = "42b7ed8fd9aefd3f36e5f617afd5071245c67853"; # hl0.56.0.1
          hash = "sha256-iK0vERuy5aXisDXm/bzcJP0dgaIot5MLPoVG62DjqO4=";
        };
        version = "0.56.0.1";
        patches =
          (old.patches or [])
          ++ [
            ../overlays/0001-fix-make-root-node-layout-truly-immutable-in-setLayo.patch
            # hy3:groupwith / hl.plugin.hy3.group_with -- nest the focused node
            # with its neighbour into a new group of a chosen orientation.
            ../overlays/0002-feat-hy3-groupwith-dispatcher.patch
            # hl.plugin.hy3.dump_tree(path)() -- write the active workspace's
            # node tree to <path> as JSON (structure-aware detection for
            # hy3-project; consumed instead of guessing layout from geometry).
            ../overlays/0003-feat-hy3-dump-tree-dispatcher.patch
            # dump_tree(path, ws) optional workspace id + dump_all(path) for all
            # workspaces -- lets hy3-layout `show --wk N/--wk all` read a
            # non-active workspace's tree without switching to it.
            ../overlays/0004-feat-hy3-dump-tree-workspace-scope.patch
          ];
      });
      firefox-devedition-bin = inputs.firefox.packages.${prev.stdenv.hostPlatform.system}.firefox-devedition-bin.override {
        extraPolicies = {
          DisableTelemetry = true;
        };
      };
    };
  };
  baseDesktop = [
    inputs.nix-vscode-extensions.overlays.default
    inputs.nix-your-shell.overlays.default
    inputs.rust-overlay.overlays.default
    # (import ./pkgs/charles)
    wayland
    figma-linux
    # fastanime
  ];
  # TODO: decide if abstracting this is worthwhile.
  overlayList = {};
  mkOverlay = {channel ? ""}: let
    overlays = ["base" "nixosMinimal" "nixosDesktop" "homeManagerMinmal" "homeManagerDesktop"];
  in
    map (o: {
      name = o;
      value = overlayList."${o}";
    })
    overlays;
  base = [
    channels
    inputs.flake-playground.overlays.default
    pam_rssh
  ];
in {
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
      ++ [inputs.llm-agents.overlays.shared-nixpkgs];
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
    homeManagerDesktop = [
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
      ++ [inputs.llm-agents.overlays.shared-nixpkgs];
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
    homeManagerDesktop = [
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
  };
}
