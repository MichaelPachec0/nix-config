{inputs, ...}: let
in {
  stable = let
  in {
    homeManager = [
      inputs.home-manager-stable.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
      }
    ];
  };
  unstable = let
    homeManager =
      inputs.home-manager.nixosModules.default
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = inputs;
      };
  in {
    homeManager = [homeManager];
  };
}
