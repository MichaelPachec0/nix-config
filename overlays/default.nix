{
  inputs,
  ...
}: {
  # additions = final: _: import ./pkgs { pkgs = final; };
  modifications = {
    common = _final: _prev: {
    };
    nixos = _final: _prev: {
    };
  };
  unstablePackages = final: _: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
