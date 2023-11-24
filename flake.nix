{
  description = " Nix infrastructure config";

  inputs = {
    nixpkgs = {url = "nixpkgs/nixos-23.05";};
    nixpkgs-unstable = {url = "nixpkgs/nixos-unstable";};
    home-manager = {
      # TODO: Decide whether to either to move on using 23.05 (once it gets stable) or revert back to hm-22.11 or the hackiest
      # way, overlay the file with one from unstable.
      # it will probably be easier to move to 23.05 as there are some options that are not avaible in the hm-22.11 branch.
      # For now, stick to a revsion before the breaking change. This should not be a problem since following an unstable channel
      # should give the required function with the right arguments (unless misunderstood).
      url =
        # if using 22.11
        #"github:nix-community/home-manager/6a1922568337e7cf21175213d3aafd1ac79c9a2e";
        "github:nix-community/home-manager";
    };
    hardware = {url = "github:nixos/nixos-hardware/master";};

    hyprland = {
      # NOTE: for some reason even with follows removed or follows set to nixpkgs-unstable hyprland builds after this commit
      # use a version of the wayland-protocols dependecy that is older than what i set it.
      # todo: (low prio) (research) find out why this happens.
      url = "github:hyprwm/hyprland/76d4a50af3db7f2123d580eb7520f5b2956f261f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kmonad-pkgs = {url = "github:kmonad/kmonad?dir=nix";};

    nwg-displays-pkgs = {url = "github:nwg-piotr/nwg-displays";};

    nixpkgs-wayland = {url = "github:nix-community/nixpkgs-wayland";};

    spicetify = {url = "github:the-argus/spicetify-nix";};

    nix-your-shell = {
      url = "github:MercuryTechnologies/nix-your-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixneovimplugins.url = "github:jooooscha/nixpkgs-vim-extra-plugins";
    nixneovim.url = "github:nixneovim/nixneovim";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # this is for pr's that have not been merged yet.
    slh.url = "github:MatthewCroughan/nixpkgs/mc/systemd-lock-handler";
  };
  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;
    unstable = import nixpkgs-unstable {
      config.allowUnfree = true;
      system = "x86_64-linux";
      overlays = [];
    };
    overlayUnstable = final: prev: {inherit unstable;};
    baseModules = [
      ({
        config,
        pkgs,
        lib,
        ...
      }: {
        nixpkgs.overlays = [
          overlayUnstable
          inputs.hyprland.overlays.default
          inputs.nix-vscode-extensions.overlays.default

          (final: prev: {
            vimPlugins =
              prev.vimPlugins
              // {
                vimBeGood =
                  import ./pkgs/vimPlugins/vim-be-good {inherit pkgs;};
                coc-lightbulb =
                  import ./pkgs/vimPlugins/coc-lightbulb {inherit pkgs;};
                coc-elixir =
                  import ./pkgs/vimPlugins/coc-elixir {inherit pkgs;};
                stay-centered =
                  import ./pkgs/vimPlugins/stay-centered {inherit pkgs;};
                block-nvim =
                  import ./pkgs/vimPlugins/block-nvim {inherit pkgs;};
                indentmini =
                  import ./pkgs/vimPlugins/indentmini {inherit pkgs;};
                virt-column =
                  import ./pkgs/vimPlugins/virt-column {inherit pkgs;};
                wtf-nvim =
                  import ./pkgs/vimPlugins/wtf-nvim {inherit pkgs;};
                nvim-dap-repl-highlights =
                  import ./pkgs/vimPlugins/nvim-dap-repl-highlights {inherit pkgs;};
                neoai-nvim =
                  import ./pkgs/vimPlugins/neoai {inherit pkgs;};
                osv-nvim =
                  import ./pkgs/vimPlugins/ossfv {inherit pkgs;};
              };
            powertop-git = prev.unstable.powertop.overrideAttrs (oldAttrs: {
              version = "2.15-pre";
              src = prev.fetchFromGitHub {
                owner = "fenrus75";
                repo = oldAttrs.pname;
                rev = "b6d1569203f32ec1c2aaa065d05961c552a76a6f";
                hash = "sha256-JUqzyYyv2zi3UpuSnvjiJwecp9yYomlif6kla1wv7ZM=";
              };
              buildInputs = [
                prev.gettext
                prev.libnl
                prev.libtraceevent
                prev.libtracefs
                prev.ncurses
                prev.pciutils
                prev.zlib
              ];
            });
            swaylock-effects-pr =
              pkgs.unstable.swaylock-effects.overrideAttrs
              (oldAttrs: {
                version =
                  lib.strings.concatStrings [oldAttrs.version "-unstable"];
                patches =
                  (oldAttrs.patches or [])
                  ++ [
                    ./overlays/swaylock_effects/4_disp_img_insd_ind.patch
                    ./overlays/swaylock_effects/37_cairo_bilinear.patch
                    ./overlays/swaylock_effects/38_red_screen_fix.patch
                    ./overlays/swaylock_effects/8_change_state_strings.patch
                    ./overlays/swaylock_effects/32_unlock_on_USR1_accept_input.patch
                  ];
              });
            electron-mail-latest =
              prev.callPackage ./pkgs/electron-mail {};
            inherit (inputs.slh.legacyPackages.${prev.system}) systemd-lock-handler;
            nw = let
              nw-pkgs = inputs.nixpkgs-wayland.packages.${prev.system};
            in
              nw-pkgs
              // {
              };
          })
        ];
      })
    ];
    nixosModules =
      baseModules
      ++ [
        inputs.nixneovim.nixosModules.nixos-22-11
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    homeManagerModules =
      baseModules
      ++ [inputs.nixneovim.nixosModules.homeManager-22-11];
  in {
    # overlays = import ./overlays {inherit inputs;};
    nixosConfigurations = with nixpkgs.lib; {
      nyx = nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = nixosModules ++ [./nixos/nyx/configuration.nix];
      };
      kore = nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = nixosModules ++ [./nixos/kore/configuration.nix];
      };
    };

    homeConfigurations = with home-manager.lib; {
      "michael-nyx" = let
        system = "x86_64-linux";
      in
        homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {inherit inputs outputs;};
          modules = homeManagerModules ++ [./hm/home.nix];
        };
    };
  };
}
