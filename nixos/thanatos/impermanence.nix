{ lib, config, ... }:
{
  # Ephemeral root ("erase your darlings") for the new two-btrfs layout.
  # Imported ONLY by the `thanatos` (new drive) flake output.

  # Rollback runs in stage-1; systemd initrd is required (and is the right
  # choice with lanzaboote). btrfs tools must be present in the initrd.
  boot.initrd.systemd.enable = true;
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  # Restore the pristine root snapshot on every boot, before / is mounted.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback btrfs root subvolume to a pristine snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "systemd-cryptsetup@cryptsystem.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      mkdir -p /mnt
      mount -t btrfs -o subvol=/ /dev/mapper/cryptsystem /mnt
      # Delete any subvolumes nested under root, deepest first: a reverse
      # lexical sort orders a descendant (whose path extends its parent's)
      # before its ancestor, so no parent is deleted before its children.
      # Handles arbitrarily nested subvols; a no-op when there are none.
      # cut+sort only (coreutils, in the systemd initrd) -- no awk.
      btrfs subvolume list -o /mnt/root | cut -f9 -d' ' | sort -r \
        | while read -r sub; do btrfs subvolume delete "/mnt/$sub"; done
      btrfs subvolume delete /mnt/root
      btrfs subvolume snapshot /mnt/root-blank /mnt/root
      umount /mnt
    '';
  };

  # /tmp is a persistent subvol, not tmpfs; clear it each boot.
  boot.tmp.cleanOnBoot = true;

  # Fully declarative users, so /etc/{passwd,shadow,group,subuid,subgid}
  # need no persistence (UID/GID stability comes from /var/lib/nixos).
  # mkForce: nyx/configuration.nix (shared) sets mutableUsers = true.
  users.mutableUsers = lib.mkForce false;

  # Monthly integrity scrub of all btrfs filesystems (system + home).
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # boot-critical
      "/var/lib/sbctl"          # lanzaboote Secure Boot keys
      "/var/lib/sops-nix"       # sops age key; gates secrets incl login password
      "/var/lib/nixos"          # stable uid/gid allocation
      "/var/lib/systemd"        # random-seed, timers, coredumps
      "/var/lib/zerotier-one"   # ZeroTier node identity
      # confirmed services
      "/var/lib/NetworkManager"
      "/etc/NetworkManager/system-connections"
      "/var/lib/bluetooth"
      "/var/lib/fprint"
      "/var/lib/cups"
      "/etc/cups"
      "/var/lib/containers"     # rootful podman (dockerCompat)
      "/var/lib/libvirt"
      "/var/lib/flatpak"
      "/var/lib/syncthing"
      "/var/lib/waydroid"
      "/etc/windscribe"         # windscribe config/creds (WS_POSIX_CONFIG_DIR)
      # display state
      "/var/lib/colord"         # ICC device/profile assignments (until ICC is declarative)
    ]
    # Only persisted once the corresponding service is enabled; both default
    # to false, so these no-op until then (upower is planned for thanatos).
    ++ lib.optional config.services.hardware.bolt.enable "/var/lib/boltd"  # Thunderbolt (boltd) device authorizations
    ++ lib.optional config.services.upower.enable "/var/lib/upower";       # battery/power-usage history
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  # Read the sops age key straight from /persist rather than the bind-mount
  # aliases /etc/ssh and /var/lib/sops-nix that the shared nyx config points at.
  # sops decrypts `michael-password` (neededForUsers) in a pre-users activation
  # script that has no ordering dependency on any mount, so it runs BEFORE
  # impermanence establishes those binds -- and inside the nixos-install chroot
  # the binds never exist at all. /persist is neededForBoot (mounted in the
  # initrd), so these real paths are always populated when sops needs them.
  # Without this, decrypting the login password races the mounts and fails,
  # aborting activation (switch-to-configuration exit 4).
  sops.age.sshKeyPaths = lib.mkForce [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  sops.age.keyFile = lib.mkForce "/persist/var/lib/sops-nix/key.txt";
}
