{
  description = "Nix infrastructure config";

  inputs = {
    # NOTE: keeping stable so that stable packages (sway) can be accessed, and when using defining system on server.
    # IF LOGIN FAILS REMOVE THIS, this is also used because cross compilation of arm64 UEFI does not work on current stable.
    nixpkgs-oldstable = {url = "nixpkgs/nixos-23.05";};
    nixpkgs-stable = {url = "nixpkgs/nixos-26.05";};
    nixpkgs = {url = "nixpkgs/nixos-unstable";};
    nixpkgs-master = {url = "nixpkgs/master";};
    nixpkgs-unstable-small.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # hardware.url = "github:nixos/nixos-hardware";
    hardware.url = "github:MichaelPachec0/nixos-hardware";

    # NOTE: Hyprland and hy3 now come from nixpkgs (pkgs.hyprland +
    # pkgs.hyprlandPlugins.hy3). nixpkgs' hyprlandPlugins scope builds hy3
    # against the same nixpkgs hyprland, so the plugin ABI matches without
    # pinning the Hyprland flake to a tag and compiling it from source. See
    # helpers/overlays.nix (latest.hyprland / latest.hy3).
    swayfx = {
      url = "github:WillPower3309/swayfx";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    kmonad-pkgs = {
      url = "github:kmonad/kmonad?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    spicetify = {
      url = "github:MichaelPachec0/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tch-nvim = {
      url = "github:MichaelPachec0/telescope-cheat.nvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-your-shell = {
      url = "github:mercurytechnologies/nix-your-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # for devshell
    flake-utils.url = "github:numtide/flake-utils";

    nixd = {
      url = "github:nix-community/nixd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    waybar-git = {
      url = "github:Alexays/Waybar";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rustaceanvim = {
      url = "github:mrcjkb/rustaceanvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # mozilla.url = "github:mozilla/nixpkgs-mozilla";
    joshuto = {
      url = "github:kamiyaa/joshuto";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
    };
    jlink = {
      # 2025-11-18: this gets tied to 874a, which is should have a download at all times for
      url = "github:liff/j-link-flake/a0a98d3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mpv-ai-upscale = {
      url = "github:Alexkral/AviSynthAiUpscale";
      flake = false;
    };
    anime4k = {
      url = "github:bloc97/Anime4K";
      flake = false;
    };
    fastanime = {
      url = "github:MichaelPachec0/FastAnime";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Broadcom firmware for the Apple T2 (aphrodite), extracted from macOS and
    # not redistributable via nixpkgs; consumed as a plain source tree.
    t2-apple-fw = {
      url = "github:RNGDesign/t2-apple-fw/d25434275e67a4230f1c5d27f0e32a41fb5de404";
      flake = false;
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-playground = {
      url = "github:MichaelPachec0/flake-playground";
      # INFO: for local building
      # url = "path:/home/michael/git/personal/flake-playground";
    };
    lanzaboote = {
      # 2025-11-11: graduated to the stable v1.1.0 relase
      url = "github:nix-community/lanzaboote/v1.1.0";

      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tuwunel = {
      url = "github:matrix-construct/tuwunel/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox = {
      url = "github:nix-community/flake-firefox-nightly";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scenefx = {
      # 2025-11-19: flake.nix for swayfx is month old
      # url = "github:wlrfx/scenefx/b92dcb43bcf0da17ba8bfbdd7385dce75383628c";
      url = "github:wlrfx/scenefx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-for-linux = {
      url = "github:MichaelPachec0/claude-for-linux";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    glide = {
      url = "github:glide-browser/glide.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    ncspot = {
      url = "github:MichaelPachec0/ncspot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    home-manager-stable,
    flake-utils,
    ...
  } @ inputs: let
    inherit (self) outputs;

    overlays = import ./helpers/overlays.nix {inherit inputs;};
    # Single source of truth for per-user HM module lists, shared with the
    # integrated NixOS path (features/nixos/home).
    homeModules = import ./helpers/home.nix {inherit inputs;};
    thanatosSharedModules =
      overlays.unstable.nixosDesktop
      ++ [
        inputs.hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen1
        inputs.lanzaboote.nixosModules.lanzaboote
        inputs.sops-nix.nixosModules.sops
        inputs.jlink.nixosModule
        inputs.flake-playground.nixosModules.default
        ./nixos/nyx/boot.nix
        ./nixos/nyx/configuration.nix
        ./nixos/thanatos/amd.nix
        ./nixos/thanatos/hardware-configuration.nix
        inputs.disko.nixosModules.disko
        ./nixos/thanatos/e5800.nix
        ./nixos/thanatos/ec-pd.nix
        ./nixos/thanatos/memory.nix
        ./features/nixos/common/nix-access-tokens.nix
        {
          services.e5800 = {
            enable = true;
            cycleResetDay = 1;
          };
          # DISABLED: reading EC RAM via ec_sys drives a gpe03 (EC SCI) storm
          # (~700-1000/s) that starves the EC's keyboard-matrix scan -> late key
          # releases / dropped keys (the "sticky keyboard"). Proven by isolation:
          # stopping ec-pd-poll drops gpe03 from ~700/s to ~4/s. The reads
          # themselves are the trigger (each RD_EC interleaves with the EC's query
          # protocol); it is NOT fixed by a reboot or a full battery drain because
          # the poller re-arms it every boot. Do not re-enable without a
          # storm-safe EC read path.
          services.ecPd.enable = false;
          local.nixAccessTokens.enable = true;
        }
      ];
    mkThanatos = extraModules:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = thanatosSharedModules ++ extraModules;
      };
  in {
    # overlays = import ./overlays {inherit inputs;};
    nixosConfigurations = {
      nyx = let
        system = "x86_64-linux";
      in
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {inherit inputs outputs;};
          # NOTE: include the stable module since this is going to run unstable.
          modules =
            overlays.unstable.nixosDesktop
            ++ [
              # changed to precision 5530/9570
              # inputs.hardware.nixosModules.dell-xps-15-9560-intel
              # inputs.hardware.nixosModules.dell-precision-5530
              inputs.hardware.nixosModules.dell-xps-15-9570-intel
              # secure boot
              inputs.lanzaboote.nixosModules.lanzaboote
              inputs.sops-nix.nixosModules.sops
              inputs.flake-playground.nixosModules.default
              ./nixos/nyx/configuration.nix
              ./nixos/nyx/hardware-configuration.nix
              ./nixos/nyx/intel.nix
              ./nixos/nyx/boot.nix
              ./nixos/nyx/extras.nix
            ];
        };
      thanatos = mkThanatos [
        ./nixos/thanatos/disk-config.nix
        inputs.impermanence.nixosModules.impermanence
        ./nixos/thanatos/impermanence.nix
      ];
      thanatos-legacy = mkThanatos [
        ./nixos/thanatos/disk-config.ext4-legacy.nix
      ];
      aphrodite = let
        system = "x86_64-linux";
      in
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {inherit inputs outputs;};
          # NOTE: include the stable module since this is going to run unstable.
          modules =
            overlays.unstable.nixosDesktop
            ++ [
              inputs.hardware.nixosModules.apple-t2

              inputs.sops-nix.nixosModules.sops
              # nyx/configuration.nix (shared below) sets hardware.cynthion,
              # hardware.zsa and services.windscribe, all defined by
              # flake-playground's default module. Import it here too so the
              # shared config evaluates (matches nyx/thanatos).
              inputs.flake-playground.nixosModules.default
              # shared laptop config
              # TODO: move away from here
              ./nixos/nyx/configuration.nix
              # inputs.disko.nixosModules.disko
              ./nixos/aphrodite/apple.nix
              ./nixos/aphrodite/extras.nix
              ./nixos/aphrodite/hardware-configuration.nix
            ];
        };
      # NOTE: This will always use stable version of nixos.
      # TODO: make sure that there is a boolean value (isServer?) to ensure that we pick packages in the stable branch.
      kore = nixpkgs-stable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        # modules = nixosModules ++ overlayModule ++ [./nixos/kore/configuration.nix];
        # modules = overlay.nixos ++ overlay.channels ++ [./nixos/kore/configuration.nix];
        # modules = [overlays.stable.nixosServer externalModules.stable.homeManager] ++ [./nixos/kore/configuration.nix];
        modules =
          overlays.stable.nixosServer
          ++ [
            inputs.impermanence.nixosModules.impermanence
            inputs.disko.nixosModules.disko
            ./nixos/kore/configuration.nix
            ./features/nixos/home/server.nix
          ];
        # ++ externalModules.stable.homeManager;
        # ++ ;
      };
      # This is commented out because there is no configuration.nix, which during a nix flake check, is checked for a root partition.
      # These machines are not available but for future use.:which.
      # NOTE: This is the server in the sky, perfect naming
      #   this also follows the nixos stable like local server.
      #   Given the small footprint, this also wont have as many packages as local, should not be a problem as zerotier will be
      #   running on both.
      # NOTE: Remote x86 server on RN.
      atlas = nixpkgs-stable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules =
          overlays.stable.nixosServer
          ++ [
            inputs.impermanence.nixosModules.impermanence
            inputs.disko.nixosModules.disko
            ./nixos/atlas/configuration.nix
            ./features/nixos/home/server.nix
          ];
      };
      # Ampere instance
      # while it is preferable to keep with the greek mythos (selene), i just prefer the name luna :)
      #NOTE: Remote arm64 server on OC
      selene = nixpkgs-stable.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs outputs;};
        modules =
          overlays.stable.nixosServer
          ++ [
            inputs.disko.nixosModules.disko
            ./nixos/selene/configuration.nix

            inputs.sops-nix.nixosModules.sops
            ./features/nixos/home/server.nix
          ];
      };
      #NOTE: Remote arm64 server on OC
      # eos = nixpkgs-stable.lib.nixosSystem {
      #   system = "aarch64-linux";
      #   specialArgs = {inherit inputs outputs;};
      #   modules = nixosModules ++ [];
      # };
      alex = nixpkgs-stable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [
          ./nixos/alex/configuration.nix
        ];
      };
    };

    homeConfigurations = let
      mkHomeConfig = {
        pre_pkgs ? nixpkgs.legacyPackages,
        # extraSpecialArgs ? {inherit inputs ouputs;},
        extraSpecialArgs ? {
          inherit inputs outputs;
          # standalone `home-manager switch`; the integrated NixOS path
          # (features/nixos/home) passes standalone = false. Module args do not
          # honor `? true` defaults, so it must be supplied here for every config.
          standalone = true;
        },
        modules ?
          overlays.unstable.homeManagerDesktop
          ++ [./hm/home.nix],
        system ? "x86_64-linux",
        hm-instance ? home-manager,
      }:
        hm-instance.lib.homeManagerConfiguration {
          pkgs = pre_pkgs.${system};
          inherit extraSpecialArgs modules;
        };
    in {
      "michael-nyx" = mkHomeConfig {
        hm-instance = inputs.home-manager;
        modules = homeModules.mkHomeModules {
          entry = ./hm/home.nix;
          perHost = [./hm/home-nyx.nix];
        };
      };
      "michael-thanatos" = mkHomeConfig {
        hm-instance = inputs.home-manager;
        modules = homeModules.mkHomeModules {
          entry = ./hm/home.nix;
          perHost = [./hm/home-thanatos.nix];
        };
      };
      "ubuntu-distrobox" = mkHomeConfig {
        modules =
          overlays.unstable.homeManagerDesktop
          ++ [
            ./hm/home-test.nix
          ];
      };
      # TODO: configure home-manager stable for server configs.
      # Also decide if its prefered to keep these seperate (as-is) or to integrate into nixosSystem
      # NOTE: these users are on nixos stable, which is compatible with home-manager-stable.

      # NOTE: Local server.
      "sysadmin-kore" = mkHomeConfig {
        pre_pkgs = nixpkgs-stable.legacyPackages;
        hm-instance = inputs.home-manager-stable;
        modules =
          overlays.stable.homeManagerDesktop
          ++ [
            ./hm/sysadmin.nix
          ];
      };
      # NOTE: Remote x86 server on RN.
      "sysadmin-helios" = mkHomeConfig {
        pre_pkgs = nixpkgs-stable.legacyPackages;
        hm-instance = inputs.home-manager-stable;
        modules =
          overlays.stable.homeManagerDesktop
          ++ [
            ./hm/sysadmin.nix
          ];
      };
      #NOTE: Remote arm64 server on OC
      "sysadmin-luna" = mkHomeConfig {
        pre_pkgs = nixpkgs-stable.legacyPackages;
        hm-instance = inputs.home-manager-stable;
        modules =
          overlays.stable.homeManagerDesktop
          ++ [
            ./hm/sysadmin.nix
          ];
        system = "aarch64-linux";
      };
      #NOTE: Remote arm64 on OC
      "sysadmin-eos" = mkHomeConfig {
        pre_pkgs = nixpkgs-stable.legacyPackages;
        hm-instance = inputs.home-manager-stable;
        modules =
          overlays.stable.homeManagerDesktop
          ++ [
            ./hm/sysadmin.nix
          ];
        system = "aarch64-linux";
      };
    };
    # TODO: (low prio) still working on this, dont know if going to keep this, but at least this should make it easy start.
    # might be worthwhile if this is starting out from a recovery disk since this can install needed pkgs in the future (like sops, alejandra, nil_ls, neovim ect)
    devShells."x86_64-linux" = import ./shell.nix {pkgs = nixpkgs.legacyPackages."x86_64-linux";};
    checks."x86_64-linux" = {
      # Boots greetd with the qsGreeter backend under a real compositor
      # (offscreen QT_QPA_PLATFORM everywhere else in this plan never
      # constructs a PanelWindow at all) and asserts the session list is
      # generated, settings and the skin resolve, the layer-shell surfaces
      # actually render, and no credential reaches the log.
      qs-greeter = import ./pkgs/qs-greeter/nixos-test.nix {
        pkgs = nixpkgs.legacyPackages."x86_64-linux";
      };
    };
    # packages = {
    #
    #   }
    # apps."x86_64-linux" = let
    #   # pkgs = prepNixpkgs inputs.nixpkgs "x86_64-linux";
    #   pkgs = nixpkgs.legacyPackages."x86_64-linux";
    # in {
    #   update-vim-plugins = {
    #     type = "app";
    #     program = let
    #       update-vim-plugins =
    #         pkgs.writeShellScriptBin "update-vim-plugins"
    #         ''
    #           ${pkgs.vimPluginsUpdater}/bin/vim-plugins-updater \
    #               --nixpkgs ${builtins.toString nixpkgs}
    #         '';
    #       # -i /neovim-plugins.txt \
    #       # -o /neovim-plugins-generated.nix --no-commit \
    #     in "${update-vim-plugins}/bin/update-vim-plugins";
    #   };
    # };
  };
}
