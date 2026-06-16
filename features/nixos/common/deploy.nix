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
      commands = [
        {
          command = "/run/current-system/sw/bin/nix-store";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/nix-env";
          options = ["NOPASSWD"];
        }
        {
          command = ''
            /bin/sh -c "readlink -e /nix/var/nix/profiles/system || readlink -e /run/current-system"'';
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/nix-collect-garbage";
          options = ["NOPASSWD"];
        }
        # NOTE: pre 23.11 this was the way systems were reconfigured (auc), newer systems uses systemd-run and env
        {
          command = "/nix/store/*/bin/switch-to-configuration";
          options = ["NOPASSWD"];
        }
        # NOTE: this is needed for 23.11
        # https://nixos.org/manual/nixos/stable/release-notes#sec-release-23.11-nixos-breaking-changes
        {
          command = "/run/current-system/sw/bin/systemd-run";
          options = ["NOPASSWD"];
        }
        # NOTE: this is also needed for 23.11
        # $ ssh -o ControlMaster=auto -o ControlPath=/tmp/nixos-rebuild.hyg5TQ/ssh-%n -o ControlPersist=60 -t deploy@kore sudo --preserve-env=NIXOS_INSTALL_BOOTLOADER -- env -i LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive NIXOS_INSTALL_BOOTLOADER= /nix/store/wb3gf1755j2f0vc7ag46hjfvmbvcldfw-nixos-system-kore-23.11.20240222.3cb4ae6/bin/switch-to-configuration switch
        # PTY allocation request failed
        #
        # ... trancated for brevity ...
        #
        # sudo: a password is required
        {
          command = "/run/current-system/sw/bin/env";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/ln";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/nix-copy-closure";
          options = ["NOPASSWD"];
        }

        # {
        #   command = "/run/current-system/sw/bin/systemd-run -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER --collect --no-ask-password --pty --quiet --same-dir --service-type=exec --unit=nixos-rebuild-switch-to-configuration --wait true";
        #   options = [ "NOPASSWD" ];
        # }
        # {
        #   command = "/run/current-system/sw/bin/systemd-run -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER --collect --no-ask-password --pty --quiet --same-dir --service-type=exec --unit=nixos-rebuild-switch-to-configuration --wait /nix/store/*/bin/switch-to-configuration *";
        #   options = [ "NOPASSWD" ];
        # }

        # for deploy-rs
        {
          command = "/nix/store/*/activate-rs";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/rm /tmp/deploy-rs-canary-*";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}
