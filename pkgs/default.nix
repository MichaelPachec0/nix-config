{ pkgs ? (import ../helpers/nixpkgs.nix) { } }: {
  shikane = pkgs.callPackage ./shikane { };
}
