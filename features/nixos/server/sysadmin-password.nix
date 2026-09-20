# Sysadmin login hash from sops, for server hosts that import sops-nix.
#
# Kept out of base.nix on purpose: sops-nix is imported per host (selene
# today, kore and atlas later), and a host without it has no `sops` option
# tree, so any reference to config.sops there fails evaluation. Import this
# module next to base.nix once the host has sops.defaultSopsFile and its age
# recipient in secrets/default.yaml.
{config, ...}: {
  users.users.sysadmin.hashedPasswordFile =
    config.sops.secrets."users/sysadmin/password".path;

  # neededForUsers: decrypted before user setup, required with
  # users.mutableUsers = false.
  sops.secrets."users/sysadmin/password".neededForUsers = true;
}
