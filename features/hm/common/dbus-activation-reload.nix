# Reload the user session bus after a switch so it re-reads its D-Bus service
# units -- dbus-broker caches them at session start, so activated services keep
# launching the previous store path. reload, never restart: a restart drops
# every session-bus connection. NixOS side in features/nixos/common/default.nix.
{
  pkgs,
  lib,
  ...
}: {
  home.activation.reloadDbusActivation =
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      run ${pkgs.systemd}/bin/systemctl --user reload dbus.service || true
    '';
}
