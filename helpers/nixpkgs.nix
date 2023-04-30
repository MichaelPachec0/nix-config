let
  flakeNixPkgs =
    (builtins.fromJSON (builtins.readFile ../flake.lock)).nodes.nixpkgs.locked;
in import (fetchTarball {
  url = "https://github.com/nixos/nixpkgs/archive/${flakeNixPkgs.rev}.tar.gz";
  sha256 = flakeNixPkgs.narHash;
})
