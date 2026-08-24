# Standalone wrapper so this directory can be copied anywhere and run with
#
#   nix run .
#
# The package itself is ./default.nix and takes plain callPackage arguments, so
# a host repo can consume it directly and ignore this file.
{
  description = "Detect a Wayland compositor that strands a client-allocated ext_session_lock_surface_v1 id";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    # No flake-utils input: one fewer thing to pin for a single-file tool.
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: rec {
      hypr-lock-strand-repro = pkgs.callPackage ./default.nix {};
      default = hypr-lock-strand-repro;
    });

    # `nix run` resolves this through meta.mainProgram, but naming it explicitly
    # keeps `nix run .#check` working if more entry points get added later.
    apps = forAllSystems (pkgs: rec {
      hypr-lock-strand-repro = {
        type = "app";
        program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.hypr-lock-strand-repro;
      };
      default = hypr-lock-strand-repro;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = [pkgs.wayland pkgs.wayland-scanner pkgs.wayland-protocols pkgs.pkg-config];
      };
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
