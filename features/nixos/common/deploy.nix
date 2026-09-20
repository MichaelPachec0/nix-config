{pkgs, ...}: let
  keys = import ../../../helpers/keys.nix;
in {
  # make sure that this user is allowed to manipulate the store.
  nix.settings.allowed-users = ["deploy"];
  users.groups.deploy = {};
  users.users.deploy = {
    isSystemUser = true;
    group = "deploy";
    shell = pkgs.bash;

    # michael's YubiKey sk-keys + thanatos, restricted with no-pty (see ../../../helpers/keys.nix).
    openssh.authorizedKeys.keys = map (k: "no-pty ${k}") keys.all;
  };
  security.sudo.extraRules = [
    {
      groups = ["deploy"];
      # nixos-rebuild --target-host runs many root commands through this
      # account (nix-store, nix-env, systemd-run, env, switch-to-configuration,
      # plus the deploy-rs activate-rs and canary paths), and the set changes
      # per release. One ALL rule replaces the per-path list. SETENV: the
      # rebuild passes --preserve-env=NIXOS_INSTALL_BOOTLOADER. The account
      # stays key-only and no-pty (see users.users.deploy above).
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD" "SETENV"];
        }
      ];
    }
  ];
}
