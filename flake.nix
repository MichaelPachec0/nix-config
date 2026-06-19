{
  description = "Nix infrastructure config";

  inputs = {
    # NOTE: keeping stable so that stable packages (sway) can be accessed, and when using defining system on server.
    # IF LOGIN FAILS REMOVE THIS, this is also used because cross compilation of arm64 UEFI does not work on current stable.
    nixpkgs-oldstable = {url = "nixpkgs/nixos-23.05";};
    # nixpkgs-stable = {url = "nixpkgs/nixos-25.05";};
    nixpkgs-stable = {url = "nixpkgs/nixos-25.11";};
    # nixpkgs-stable = {url = "nixpkgs/nixos-23.11";};
    # NixOS/nixpkgs/2057814051972fa1453ddfb0d98badbea9b83c06
    nixpkgs = {url = "nixpkgs/nixos-unstable";};
    # NOTE: this is without nixos tests being done (ie does the installer work, DE's ...ect)
    # a4073ec70f298e2941f4d3a7a0542135a9d24d04
    nixpkgs-master = {url = "nixpkgs/master";};
    nixpkgs-unstable-small.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      # inputs.nixpkgs.follows = "nixpkgs-treesitter";
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
      url = "github:WillPower3309/swayfx?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
      # 2025-11-19: flake.nix for swayfx is month old
      inputs.scenefx.follows = "scenefx";
    };

    kmonad-pkgs = {
      url = "github:kmonad/kmonad?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nwg-displays-pkgs = {
    #   url = "github:nwg-piotr/nwg-displays";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    spicetify = {
      # url = "github:MichaelPachec0/spicetify-nix/fix-snap-err";
      url = "github:MichaelPachec0/spicetify-nix";
      # url = "path:/home/michael/old/git/github/personal/nix/repos/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # spicetify = {url = "path:/home/michael/old/git/github/personal/nixos-config-actual/repos/spicetify-nix";};
    # tch-nvim = {url = "path:/home/michael/old/git/github/forked/telescope-cheat.nvim";};
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

    # this is for pr's that have not been merged yet.
    # TODO: check if these have been merged into nixpkgs
    # slh.url = "github:matthewcroughan/nixpkgs/mc/systemd-lock-handler";
    # git-oxide.url = "github:jalil-salame/nixpkgs/fix-gitoxide";
    # for devshell
    flake-utils.url = "github:numtide/flake-utils";
    # for cody
    # TODO: move from using this to regular nixpkgs or create an overlay
    # that uses this as the package.

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
      # NOTE: this is based on nightly from 2024-02-18 issues abound with some plugins (my version of lspconfig)
      # inputs.neovim-flake.url = "github:neovim/neovim?dir=contrib&rev=8f1f2a1d9f6af56ae928f6cdc29055a0ba13baea";
    };
    # mozilla.url = "github:mozilla/nixpkgs-mozilla";
    joshuto = {
      url = "github:kamiyaa/joshuto";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # waybar-test = {
    #   # WARN: only needed for the moment where waybar cannot compile
    #   url = "github:tokyovigilante/waybar/wireplumber-0.5";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    #    easy-tether = {
    #      # url = "github:Programmerino/easytether-flake";
    #      url = "path:/home/michael/old/git/github/personal/nixos-config-actual/repos/easytether-flake";
    #      inputs.nixpkgs.follows = "nixpkgs"; };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
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
      # WARN: MAKE SURE TO CHANGE THIS!
      # url = "path:/home/michael/git/personal/flake-playground";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      # 2025-11-11: upgraded to allow builing on unstable
      # url = "github:nix-community/lanzaboote/v0.4.3";

      # 2026-06-18 fixes nobootspec error in unstable
      # ref: https://github.com/nix-community/lanzaboote/pull/617
      url = "github:nix-community/lanzaboote/0403b4b7e8b2612657f0053a4c315e6c43eee9e6";

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
      # inputs.nixpkgs.follows = "nixpkgs";
      # inputs.flake-utils.follows = "flake-utils";
    };
    claude-code.url = "github:numtide/llm-agents.nix";
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
    # integrated NixOS path (features/nixos/home). See docs/hm-nixos-integration.md.
    homeModules = import ./helpers/home.nix {inherit inputs;};
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
              ./nixos/nyx/configuration.nix
              ./nixos/nyx/hardware-configuration.nix
              ./nixos/nyx/intel.nix
              ./nixos/nyx/boot.nix
              ./nixos/nyx/extras.nix
            ];
        };
      thanatos = let
        system = "x86_64-linux";
      in
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {inherit inputs outputs;};
          # NOTE: include the stable module since this is going to run unstable.
          modules =
            overlays.unstable.nixosDesktop
            ++ [
              inputs.hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen1
              # secure boot
              inputs.lanzaboote.nixosModules.lanzaboote
              inputs.sops-nix.nixosModules.sops
              inputs.jlink.nixosModule
              # shared laptop config
              # TODO: move away from here
              ./nixos/nyx/boot.nix
              ./nixos/nyx/configuration.nix
              ./nixos/thanatos/amd.nix
              ./nixos/thanatos/hardware-configuration.nix
              inputs.disko.nixosModules.disko
              ./nixos/thanatos/disk-config.nix
              # ./nixos/thanatos/extras.nix
            ];
        };
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
          inputs = inputs;
          outputs = outputs;
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
