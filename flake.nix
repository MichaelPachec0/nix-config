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
        ({ config, pkgs, ... }: {
          nixpkgs.overlays =
            [ overlayUnstable inputs.hyprland.overlays.default ];
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
