# Same as yubikey-gpg, but decorated to work in a erase-your-darlings
# setting.
{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.hardware.yubikey-gpg;
in {
  imports = [./default.nix];

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = concatLists (mapAttrsToList (user: opts: [
        "d /home/${user}/.gnupg - ${user} users - -"
        "L /home/${user}/.gnupg/pubring.kbx - - - - /persist/home/${user}/.gnupg/pubring.kbx"
        "L /home/${user}/.gnupg/trustdb.gpg - - - - /persist/home/${user}/.gnupg/trustdb.gpg"
      ])
      cfg.users);

    # If the home-manager service runs first, it will create the
    # .gnupg directory, but do so with "permissive" permissions.
    # GnuPG complains when the permissions on the ".gnupg" directory
    # are too loose. So we run home-manager after systemd.tmpfiles
    # has had the chance to create the directory with more
    # restrictive permissions.
    #
    # If this dependency causes problems in future we might want to
    # look at home-manager's user tmpfiles implementation.
    systemd.services = mapAttrs' (user: _:
      nameValuePair "home-manager-${user}" {
        after = ["systemd-tmpfiles-setup.service"];
      })
    cfg.users;
  };
}
