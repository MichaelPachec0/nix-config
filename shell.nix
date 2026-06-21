# Shell for bootstrapping flake-enabled nix and other tooling
let
  file = builtins.fromJSON (builtins.readFile ./flake.lock);
in
  {
    pkgs ?
    # If pkgs is not defined, instanciate nixpkgs from locked commit
    let
      buildpkgs = lock: {
        url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
        sha256 = lock.narHash;
      };
      unstableLock = file.nodes."nixpkgs-unstable".locked;
      lock = file.nodes.nixpkgs.locked;
      unstable = fetchTarball (buildpkgs unstableLock);
      nixpkgs = fetchTarball (buildpkgs lock);
    in
      import nixpkgs {
        overlays = [(final: prev: {inherit unstable;})];
      },
    ...
  }: let
    sopsLock = file.nodes."sops-nix".locked;
    sops-nix = fetchTarball {
      url = "https://github.com/Mic92/sops-nix/archive/${sopsLock.rev}.tar.gz";
      sha256 = sopsLock.narHash;
    };
  in {
    default = pkgs.mkShell {
      NIX_CONFIG = "extra-experimental-features = nix-command flakes repl-flake";
      nativeBuildInputs = with pkgs;
        [
          nix

          home-manager
          gitFull

          sops
          gnupg
          age
          (pkgs.callPackage sops-nix {}).sops-import-keys-hook
          nixos-anywhere
          python3
        ]
        ++ (with pkgs; [statix nil nixpkgs-fmt vulnix haskellPackages.dhall-nix niv lorri]);
      # imports all files ending in .asc/.gpg
      sopsPGPKeyDirs = [
        # TODO: this is already setup locally?
        # "${toString ./.}/keys/hosts"
        # "${toString ./.}/keys/users"
      ];

      # Also single files can be imported.
      #sopsPGPKeys = [
      #  "${toString ./.}/keys/users/mic92.asc"
      #  "${toString ./.}/keys/hosts/server01.asc"
      #];

      # This hook can also import gpg keys into its own seperate
      # gpg keyring instead of using the default one. This allows
      # to isolate otherwise unrelated server keys from the user gpg keychain.
      # By uncommenting the following lines, it will set GNUPGHOME
      # to .git/gnupg.
      # Storing it inside .git prevents accedentially commiting private keys.
      # After setting this option you will also need to import your own
      # private key into keyring, i.e. using a a command like this
      # (replacing 0000000000000000000000000000000000000000 with your fingerprint)
      # $ (unset GNUPGHOME; gpg --armor --export-secret-key 0000000000000000000000000000000000000000) | gpg --import
      # sopsCreateGPGHome = true;
      # To use a different directory for gpg dirs set sopsGPGHome
      #sopsGPGHome = "${toString ./.}/../gnupg";
    };
  }
