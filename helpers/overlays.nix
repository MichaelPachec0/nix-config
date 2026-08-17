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

  pam_rssh = final: prev: {
    pam_rssh = prev.callPackage ../overlays/pam_rssh {};
  };
  qsGreeter = final: prev: {
    qs-greeter = prev.callPackage ../pkgs/qs-greeter {};
  };
  latest = final: prev: {
    # Hyprland's backend, patched against permanent loss of every input device
    # present at compositor start: libinput enumerates as soon as it gets its
    # seat, and if the libseat session is not active yet (VT still being handed
    # over from the greeter) logind revokes every fd and nothing re-enumerates
    # afterwards. Leaves the session with no keyboard or touchpad at all.
    # Written against the v0.14.0 tag, which is what nixpkgs builds.
    aquamarine = prev.aquamarine.overrideAttrs (old: {
      patches = (old.patches or []) ++ [../overlays/aquamarine-libinput-inactive-session-devices.patch];
    });
    # Hyprland CORE: bumped to the v0.56.2 point release and carrying the two
    # crash patches. Overrides the TOP-LEVEL `hyprland` (not just latest.hyprland
    # below) so the compositor AND hy3 -- which builds against final.hyprland --
    # share the one binary and the plugin hash check still matches.
    #
    # nixpkgs is still on 0.56.0; we already build the compositor from source for
    # the patches, so taking the point release costs nothing extra. Both crash
    # patches re-verified against v0.56.2, and its header diff touches nothing
    # hy3 uses, so the pinned hy3 needs no source change.
    #
    # `.override` (not just `.overrideAttrs`) so the compositor links the patched
    # aquamarine above: `prev.hyprland` was instantiated against the previous
    # overlay stage, where `aquamarine` is still the stock one.
    hyprland = (prev.hyprland.override {inherit (final) aquamarine;}).overrideAttrs (old: {
      version = "0.56.2";
      src = prev.fetchFromGitHub {
        owner = "hyprwm";
        repo = "hyprland";
        fetchSubmodules = true;
        tag = "v0.56.2";
        hash = "sha256-jOcfiv+Zs2iz5oTIQcJXZ0+5MfqW0oLgGxD0cKdmXpE=";
      };
      # `hyprctl version` is fed from nixpkgs' pkgs/by-name/hy/hyprland/info.json,
      # which still describes 0.56.0 -- restate it for the bumped src, or crash
      # reports name a commit we are not running. Note the v0.56.2 tag does NOT
      # sit on the "version: bump to 0.56.2" commit (34170f65); it is one commit
      # later, on the gha inputs update, which is what the src above fetches.
      env =
        (old.env or {})
        // {
          GIT_COMMIT_HASH = "efb50993780079460b0cbed1363e2166a2de1d9f";
          GIT_COMMIT_MESSAGE = "[gha] Nix: update inputs";
          GIT_COMMIT_DATE = "2026-08-05";
          GIT_TAG = "v0.56.2";
        };
      patches =
        (old.patches or [])
        ++ [
          # Compositor SIGSEGV when the session locks while a grabbing xdg_popup
          # (a bar dropdown/menu) is open: newLock is emitted before m_locked is
          # set, so the grab is torn down with isSessionLocked() still false.
          # Still unfixed on main (SessionLock.cpp:198 is unchanged) and the
          # patch still applies there, so this one survives a future bump.
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
          ../overlays/hyprland-screencopy-dead-output-crash.patch
          # Third site in that same family and the one that actually kills the
          # bar: create_source posts a FATAL protocol error when the wl_output's
          # monitor is already gone, which the client cannot avoid because the
          # request predates global_remove. Qt answers the killed connection with
          # _exit(1), so it reads as "quickshell crashed" with no core.
          # Unlike the backport above this applies to main too, so it survives a
          # bump and is upstreamable as-is.
          ../overlays/hyprland-capture-source-stale-output.patch
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
    # Deliberately paired with the 0.56.2 compositor above, which PREDATES
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
      # Five separate bugs, all unfixed upstream as of b653ab53. Kept as separate
      # patches so each can be dropped on its own as it lands upstream; each
      # patch header carries the root cause.
      patches =
        (old.patches or [])
        ++ [
          # THE ONE THAT MATTERS. One EIS socket leaked per input-capture client
          # that goes away, each stranding its unread device advertisement as
          # IN-FLIGHT AF_UNIX fds, which sit below the kernel's GC threshold and
          # so are pinned until reboot. Past the per-UID budget every process on
          # the default 1024 RLIMIT_NOFILE loses fd passing, i.e. no GUI app can
          # connect to Wayland at all.
          ../overlays/xdph-input-capture-eis-fd-leak.patch
          # Slow leak, one fd per dmabuf format_table event, so it accumulates
          # over monitor hotplugs. Does not strand in-flight fds.
          ../overlays/xdph-dmabuf-format-table-fd-leak.patch
          # Error-path only: createBuffer's SHM branch abandons its fd where the
          # DMABUF branch above it closes correctly. Fixed for consistency.
          ../overlays/xdph-screencopy-shm-error-path-fd-leak.patch
          # SIGSEGV on EVERY session teardown, from wayland proxies marshalling
          # destroy requests onto an already-gone display at exit. On greetd that
          # is a core dump per login, which masks real portal crashes.
          ../overlays/xdph-exit-wayland-proxy-segv.patch
          # Whole desktop wedges: a Release without activation_id never reaches
          # the compositor, so input capture is never lifted -- no cursor, no
          # keys, compositor otherwise healthy, only a monitor hotplug clears it.
          # kdeconnectd omits that key on every Release.
          ../overlays/xdph-input-capture-release-without-activation-id.patch
        ];
    });
    # KDE Connect's share-input-devices plugin marshals SetPointerBarriers with
    # two wrong D-Bus signatures (`i` for barrier_id where the spec says `u`, and
    # `ai` for position where it says the struct `(iiii)`), so any portal that
    # validates the payload rejects EVERY barrier and the feature is silently
    # inert: crossing a screen edge never triggers input capture. Unfixed
    # upstream as of 26.04.3, and likely invisible on Plasma, whose Qt-based
    # portal demarshals leniently (UNVERIFIED, not tested there).
    #
    # Overriding the scope rather than the leaf so every consumer picks it up:
    # programs.kdeconnect (nixos/nyx/configuration.nix) defaults to
    # pkgs.kdePackages.kdeconnect-kde, and hm/home.nix services.kdeconnect
    # resolves it separately.
    kdePackages = prev.kdePackages.overrideScope (_kfinal: kprev: {
      kdeconnect-kde = kprev.kdeconnect-kde.overrideAttrs (old: {
        patches = (old.patches or []) ++ [../overlays/kdeconnect-inputcapture-barrier-type.patch];
      });
    });
    latest = {
      # nixpkgs ships Hyprland 0.56.0; the `hyprland` attr above bumps it to
      # v0.56.2 and carries the two crash patches. The old 0005 popup-coords
      # SIGSEGV patch is obsolete (fixed upstream in 0.56, #15416) and dropped.
      # nixpkgs' hyprlandPlugins.hy3 is still hl0.55.0, which will not load
      # against a 0.56 compositor, so hy3's src is pinned to the matching
      # hl0.56.0.1 release (see the hy3 attr below) with our patches re-applied.
      inherit (final) hyprland;
      inherit (prev) waybar;

      sway = prev.sway.override {inherit (final.nw) sway-unwrapped;};
      # nixpkgs' hy3 is hl0.55.0; pin the src to the hl0.56.0.1 release (built
      # against final.hyprland, so the plugin hash always matches whatever that
      # attr resolves to -- 0.56.2 now) and re-apply our dispatcher patches --
      # 0004 rebased onto the 0.56 workspace API (getWorkspaceByID ->
      # State::workspaceState()->query().id().run()). hl0.56.0.1 is still hy3's
      # newest tag AND its master HEAD, and neither 0.56.1 nor 0.56.2
      # removes/renames anything it uses (0.56.2 only drops InputMethodPopup
      # internals, a WorkspaceRule member default and a PointerManager signature
      # arg), so there is nothing to resync here for the point releases.
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
            # hy3:ungroup [node|group] / hl.plugin.hy3.ungroup -- lift the
            # focused node out of its group (node, the default) or dissolve the
            # whole group into its parent (group). Upstream has neither:
            # makegroup's `toggle` only collapses a single-CHILD group.
            ../overlays/0005-feat-hy3-ungroup-dispatcher.patch
          ];
      });
      firefox-devedition-bin = inputs.firefox.packages.${prev.stdenv.hostPlatform.system}.firefox-devedition-bin.override {
        extraPolicies = {
          DisableTelemetry = true;
        };
      };
    };
  };
  # Quickshell, patched -- deliberately its OWN overlay, and listed in
  # baseDesktop rather than in `latest`.
  #
  # It used to live inside the `latest` overlay, which is only in the two
  # UNSTABLE bundles. But `pkgs.quickshell` has consumers reached from `base`:
  # pkgs/qs-greeter/default.nix puts `quickshell` in the greeter's
  # runtimeInputs, and the qsGreeter overlay is in `base`, i.e. in every bundle
  # including the stable ones. So a stable desktop host resolved a
  # `pkgs.quickshell` that had NONE of this applied -- no qt6.qt5compat, so the
  # config dies at load with `module "Qt5Compat.GraphicalEffects" is not
  # installed`, and no runtime deps on PATH for the shell's helper scripts.
  # baseDesktop is the narrowest list that covers all four desktop bundles
  # (stable/unstable x nixos/homeManager), so NixOS and home-manager now get
  # the same binary by construction rather than by which channel they are on.
  # Overlays are lazy: a host that never references quickshell builds nothing.
  #
  # Patch 1: the forked PAM subprocess frees the caller's `pam_response**`
  # out-param (a stack address) on any IPC write failure, so a shell that dies
  # while a PAM child is still blocked in pam_fprintd turns into a bogus
  # "quickshell crashed" SIGSEGV report. Unfixed upstream as of 28771c7.
  #
  # Patch 2: a ScreencopyView created before its item is in a scene latches
  # WlBufferManager permanently (the retry guard is a never-reset
  # function-static), so no capture ever starts and no screencopy protocol is
  # bound. That is exactly the lock backdrop's per-output pool, whose delegates
  # are reparented into place only after the lock engages, so the backdrop
  # silently falls back to the wallpaper on every lock until the config is
  # reloaded. Also unfixed upstream as of 28771c7.
  quickshellPatched = final: prev: {
    # Patch Quickshell: the forked PAM subprocess frees the caller's
    # `pam_response**` out-param (a stack address) on any IPC write failure, so
    # a shell that dies while a PAM child is still blocked in pam_fprintd turns
    # into a bogus "quickshell crashed" SIGSEGV report. Unfixed upstream as of
    # 28771c7. Patched at the TOP-LEVEL `quickshell` so the raw `pkgs.quickshell`
    # uses (swayidle.nix, quickshell-lock.nix) and the HM module's own
    # overrideAttrs (features/hm/wayland/quickshell.nix) all stack on the fix.
    #
    # Second patch: a ScreencopyView created before its item is in a scene
    # latches WlBufferManager permanently (the retry guard is a never-reset
    # function-static), so no capture ever starts and no screencopy protocol is
    # bound. That is exactly the lock backdrop's per-output pool, whose
    # delegates are reparented into place only after the lock engages, so the
    # backdrop silently falls back to the wallpaper on every lock until the
    # config is reloaded. Also unfixed upstream as of 28771c7.
    quickshell = prev.quickshell.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [final.qt6.qt5compat];
      # wrapQtAppsHook applies these when wrapping bin/qs and bin/quickshell, so the
      # shell's child processes (bash -lc lib/*.sh) inherit the deps on PATH.
      qtWrapperArgs = let
        runtimeDeps = with final; [
          bash
          coreutils
          gnugrep
          gnused
          gawk
          bluez # bluetoothctl
          pipewire # pw-dump
          wireplumber # wpctl
          pulseaudio # pactl
          python3
          systemd # busctl (mpris-extra.sh)
          pbpctrl # Pixel Buds control (btinfo.sh pbp/set)
          wl-clipboard # wl-copy (network widget middle-click copy)
          networkmanager # nmcli (NetworkService)
          iproute2 # ip (NetworkService default-route lookup)
          awww
          # config.services.awww.package # awww query (LockBackdrop reads per-output wallpaper)
        ];
      in
        (old.qtWrapperArgs or [])
        ++ ["--prefix PATH : ${prev.lib.makeBinPath runtimeDeps}"];
      patches =
        (old.patches or [])
        ++ [
          ../overlays/quickshell-pam-conversation-invalid-free.patch
          ../overlays/quickshell-screencopy-buffer-manager-latch.patch
        ];
    });
  };

  baseDesktop = [
    quickshellPatched
    inputs.nix-vscode-extensions.overlays.default
    inputs.nix-your-shell.overlays.default
    inputs.rust-overlay.overlays.default
    # (import ./pkgs/charles)
    wayland
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
    qsGreeter
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
            inputs.nix-vscode-extensions.overlays.default
            inputs.gruvbox-gtk-theme.overlays.default
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
      ]);
    nixosDesktop =
      [
        (mkOverlayModules
          (
            base
            ++ baseDesktop
            ++ [
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
            latest
            inputs.nix-vscode-extensions.overlays.default
            inputs.gruvbox-gtk-theme.overlays.default
          ]
          ++ lspServers
        ))
    ];
  };
}
