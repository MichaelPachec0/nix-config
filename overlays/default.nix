{
  lib,
  inputs,
  pkgs,
  ...
}: {
  # additions = final: _: import ./pkgs { pkgs = final; };
  modifications = {
    common = final: prev: {
    };
    nixos = final: prev: {
    };
  };
  unstablePackages = final: _: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
