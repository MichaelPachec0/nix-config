{ pkgs, ... }: {
  users.groups.deploy = { };
  users.users.deploy = {
    isSystemUser = true;
    group = "deploy";
    shell = pkgs.bash;

    openssh.authorizedKeys.keys = [
      "no-pty sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICFSUN6IGskLmeq7ip+oTbYuE+WRLcbYGGGOAyH/ECWaAAAABHNzaDo= michael@nyx"
      "no-pty sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAKEnIsOFEp1Lx9XwZRVN+iRKyCKRiy4U9kw1JWH1UAYAAAABHNzaDo= michael@nyx"
      "no-pty "
      "no-pty "
    ];
  };

  security.sudo.extraRules = [{
    groups = [ "deploy" ];
    commands = [
      {
        command = "/nix/store/*/bin/switch-to-configuration";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/nix-store";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/nix-env";
        options = [ "NOPASSWD" ];
      }
      {
        command = ''
          /bin/sh -c "readlink -e /nix/var/nix/profiles/system || readlink -e /run/current-system"'';
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/nix-collect-garbage";
        options = [ "NOPASSWD" ];
      }
    ];
  }];
}
