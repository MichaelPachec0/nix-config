{
  description = " Nix infrastructure config";

  inputs = {
    nixpkgs = { url = "nixpkgs/nixos-22.11"; };
    nixpkgs-unstable = { url = "nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hardware = { url = "github:nixos/nixos-hardware/master"; };

    hyprland = { url = "github:hyprwm/Hyprland"; };

    kmonad-pkgs = { url = "github:kmonad/kmonad?dir=nix"; };

    nwg-displays-pkgs = { url = "github:nwg-piotr/nwg-displays"; };

    nixpkgs-wayland = { url = "github:nix-community/nixpkgs-wayland"; };

    spicetify = { url = "github:the-argus/spicetify-nix"; };

    nix-your-shell = {
      url = "github:MercuryTechnologies/nix-your-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };
  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs:
    let
      inherit (self) outputs;
      unstable = import nixpkgs-unstable {
        config.allowUnfree = true;
        system = "x86_64-linux";
        overlays = [ ];
      };
      overlayUnstable = final: prev: { inherit unstable; };
      baseModules = [
        ({ config, pkgs, lib, ... }: {
          nixpkgs.overlays = [
            overlayUnstable
            inputs.hyprland.overlays.default

            (final: prev: {
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
              swaylock-effects-pr = pkgs.unstable.swaylock-effects.overrideAttrs
                (oldAttrs: {
                  version =
                    lib.strings.concatStrings [ oldAttrs.version "-unstable" ];
                  patches = (oldAttrs.patches or [ ]) ++ [
                    ./overlays/swaylock_effects/4_disp_img_insd_ind.patch
                    ./overlays/swaylock_effects/37_cairo_bilinear.patch
                    ./overlays/swaylock_effects/38_red_screen_fix.patch
                    ./overlays/swaylock_effects/8_change_state_strings.patch
                  ];
                });
              electron-mail-latest =
                (prev.callPackage ./pkgs/electron-mail { });
            })

          ];
        })
      ];
      nixosModules = baseModules ++ [
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    in {
      # overlays = import ./overlays {inherit inputs;};
      nixosConfigurations = with nixpkgs.lib; {
        nyx = nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs outputs; };
          modules = nixosModules ++ [ ./nixos/nyx/configuration.nix ];
        };
        kore = nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs outputs; };
          modules = nixosModules ++ [ ./nixos/kore/configuration.nix ];
        };
      };

      homeConfigurations = with home-manager.lib; {
        "michael-nyx" = let system = "x86_64-linux";
        in homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit inputs outputs; };
          modules = baseModules ++ [ ./hm/home.nix ];
        };
      };
    };

}
