# thanatos Phase B — Operator Migration Runbook (STANDALONE)

Execute top to bottom. This is DESTRUCTIVE to the NEW drive only. The OLD 512G
drive is never written (mounted read-only) and is your fallback. No live
assistant is available — everything you need is here.

Related (on the old drive at `/home/michael/nix-config/docs/superpowers/`):
spec `2026-07-12-thanatos-drive-migration-impermanence-design.md`,
plan `2026-07-12-thanatos-drive-migration-impermanence.md`.

--------------------------------------------------------------------------------
## 0. CRITICAL SAFETY RULES (read first)
--------------------------------------------------------------------------------

- The NEW drive is a Crucial P310 2TB (`CT2000P310SSD8`, serial `2530519CAA98`).
  The OLD drive is a Micron 512G (`nvme-Micron_MTFDHBA512TDV_21042CF4DA27`).
- `disko` in Stage 5 ERASES the target device. Triple-check you are pointing at
  the NEW 2TB drive, not the old one and not a USB stick.
- Mount the OLD drive READ-ONLY only. It is the rollback. Do not write to it.
- Do NOT `nixos-rebuild switch/boot/test .#thanatos` on the OLD drive — ever.
  The old drive uses `.#thanatos-legacy`.
- Enter every LUKS passphrase the SAME for all three new containers, so first
  boot needs only one unlock. Recommended: reuse your current LUKS passphrase.
- If anything looks wrong and you are unsure: STOP. The old drive still boots.
  Put it back in the M.2 slot and you are exactly where you started.

## What you need
- The new P310 2TB drive.
- A recent NixOS live USB installer (24.05+ / current). You will temporarily
  DISABLE Secure Boot in firmware to boot it.
- The JMicron JMS583 USB-NVMe enclosure for the OLD drive.
- Wired or wireless network in the live environment (for `nixos-install`).
- Your current LUKS passphrase.
- A separate USB stick / external location to store LUKS header backups.

--------------------------------------------------------------------------------
## 1. PRE-FLIGHT (do this on the CURRENT running system, before shutting down)
--------------------------------------------------------------------------------

1.1  Confirm an OFF-MACHINE backup of `/home` exists (~154G). Snapshots and the
     new drive are not a backup. The old drive is your only copy during the move.

1.2  Record current identity values to compare after migration:
```
zerotier-cli info                 # note the 10-char node id
nmcli -g NAME connection show     # note expected wifi/VPN connection names
sudo sbctl status                 # note "Secure Boot" + "Installed" (keys enrolled)
fprintd-list "$USER" 2>/dev/null  # note enrolled fingerprints
```

1.3  Ensure the Phase A commits are present on the branch (they carry the new
     disk-config + impermanence + flake profiles):
```
cd /home/michael/nix-config
git log --oneline -4
# expect: c257bc9, 3812668, cb76125, cbcd6a3 (subjects: harden rollback / ephemeral
# root + dual profiles / new two-LUKS-two-btrfs layout / preserve ext4 legacy)
```
     (Signing these is optional and can be done later:
      `git rebase --exec 'git commit --amend --no-edit -S' 3b3fad1`.)

1.4  Shut down.

--------------------------------------------------------------------------------
## 2. FIRMWARE + BOOT THE LIVE USB
--------------------------------------------------------------------------------

2.1  Physically install the NEW P310 into the internal M.2 slot (removing the old
     512G drive). Put the OLD 512G drive into the JMicron USB enclosure. Do NOT
     plug the enclosure in yet.

2.2  Enter firmware setup. TEMPORARILY DISABLE Secure Boot (needed to boot the
     unsigned live USB). Disabling SB does NOT erase your enrolled keys; you will
     re-enable it in Stage 10. Set the live USB first in boot order (or use the
     one-time boot menu). Save + exit.

2.3  Boot the NixOS live USB. Open a root shell:
```
sudo -i
```

2.4  Get network up (needed for nixos-install). Wired: usually automatic
     (`ping -c1 cache.nixos.org`). Wireless: `nmtui` or
     `wpa_supplicant`/`iwctl` per the ISO. Confirm:
```
ping -c1 cache.nixos.org
```

2.5  NOW plug in the USB enclosure with the OLD drive.

--------------------------------------------------------------------------------
## 3. IDENTIFY DRIVES (do not skip — prevents wiping the wrong disk)
--------------------------------------------------------------------------------

3.1  List block devices:
```
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL,MOUNTPOINT
```
     - NEW drive: TYPE=disk, TRAN=nvme, SIZE ~1.8T, MODEL contains CT2000P310SSD8
       (device node like `/dev/nvme0n1`).
     - OLD drive: TYPE=disk, TRAN=usb, SIZE ~477G (device node like `/dev/sda`).

3.2  Confirm the NEW drive's by-id (this must match disk-config.nix):
```
ls -l /dev/disk/by-id/nvme-* | grep -i CT2000P310
```
     Expect something like:
       `nvme-CT2000P310SSD8_2530519CAA98 -> ../../nvme0n1`
     (Ignore any `-partN` entries; the whole-disk link has no `-part` suffix.
      A trailing `_1` variant may also appear — that is the namespace-specific
      alias; the base `nvme-CT2000P310SSD8_2530519CAA98` is what we use.)

3.3  Watch briefly for USB (UAS) instability on the enclosure:
```
dmesg | tail -20 | grep -i uas
```
     If you see repeated `uas_eh_abort_handler` / device resets, the JMS583 is
     misbehaving. REBOOT the live USB adding this kernel parameter (edit the boot
     entry, append to the kernel line), which forces stable BOT mode:
       `usb-storage.quirks=152d:0583:u`
     Then redo Stage 2-3.

--------------------------------------------------------------------------------
## 4. MOUNT THE OLD DRIVE (read-only) AND GET THE REPO
--------------------------------------------------------------------------------

Below, replace `/dev/sda` with the OLD drive node from Stage 3, and `X` in
`/dev/sdaN` accordingly. The old root is the ~444G `crypto_LUKS` partition.

4.1  Inspect the old drive's partitions:
```
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL /dev/sda
```
     Identify the LUKS root partition (PARTLABEL `disk-main-root`, ~444G).

4.2  Unlock and mount it READ-ONLY at /oldroot (NOT under /mnt):
```
cryptsetup open /dev/disk/by-partlabel/disk-main-root oldroot   # enter OLD passphrase
mkdir -p /oldroot
mount -o ro /dev/mapper/oldroot /oldroot
ls /oldroot/home/michael/nix-config   # sanity: the repo is here
```

4.3  Clone the repo to a writable location in the live env:
```
git clone /oldroot/home/michael/nix-config /root/nix-config
cd /root/nix-config
git log --oneline -4    # verify c257bc9, 3812668, cb76125, cbcd6a3 are present
```

4.4  VERIFY the drive by-id in disk-config matches Stage 3.2. If Stage 3.2 showed
     a different string (e.g. a trailing `_1`), edit it and STAGE the change (nix
     flakes ignore un-staged edits):
```
grep device /root/nix-config/nixos/thanatos/disk-config.nix
# if it does not match Stage 3.2, edit the file, then:
#   git -C /root/nix-config add nixos/thanatos/disk-config.nix
```

--------------------------------------------------------------------------------
## 5. FORMAT THE NEW DRIVE WITH DISKO  *** DESTRUCTIVE — NEW DRIVE ONLY ***
--------------------------------------------------------------------------------

5.1  Run disko against the disk-config FILE (not the flake). This destroys and
     re-creates the NEW drive, then mounts the new tree at /mnt:
```
nix --experimental-features "nix-command flakes" \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  /root/nix-config/nixos/thanatos/disk-config.nix
```
     You will be prompted for a LUKS passphrase THREE times (cryptswap,
     crypthome, cryptsystem). Enter the SAME passphrase all three times.

     If disko errors on existing signatures, wipe and retry:
       `wipefs -a /dev/nvme0n1` (the NEW drive) then re-run 5.1.

5.2  Verify the layout:
```
lsblk /dev/nvme0n1
findmnt /mnt /mnt/nix /mnt/persist /mnt/home /mnt/var/log /mnt/tmp
ls -l /dev/disk/by-partlabel/ | grep disk-thanatos
```
     Expect: ESP ~4G at /mnt/boot; cryptswap swap; crypthome btrfs at /mnt/home;
     cryptsystem btrfs at /mnt, /mnt/nix, /mnt/persist, /mnt/var/log, /mnt/tmp;
     partlabels disk-thanatos-{esp,swap,home,system}.

--------------------------------------------------------------------------------
## 6. SEED THE PRISTINE root-blank SNAPSHOT  (before install populates root)
--------------------------------------------------------------------------------

The ephemeral root is restored from `root-blank` on every boot. Snapshot it now,
while `root` is empty:
```
mkdir -p /mnt2
mount -o subvol=/ /dev/mapper/cryptsystem /mnt2
btrfs subvolume snapshot -r /mnt2/root /mnt2/root-blank
btrfs subvolume list /mnt2      # expect both: root AND root-blank
umount /mnt2
```

--------------------------------------------------------------------------------
## 7. INSTALL-TIME STATE THAT MUST EXIST BEFORE `nixos-install`
--------------------------------------------------------------------------------

7.1  Secure-Boot keys. lanzaboote signs the new boot image during install using
     keys in `/var/lib/sbctl`. Reusing your OLD keys (already enrolled in
     firmware) avoids re-enrollment. Place them on the new root BEFORE installing:
```
mkdir -p /mnt/var/lib
cp -a /oldroot/var/lib/sbctl /mnt/var/lib/sbctl
ls /mnt/var/lib/sbctl/keys    # sanity: db/KEK/PK keys present
```

7.2  sops age key + ssh host keys ON /persist. `nixos-install` runs activation,
     which decrypts the login password (`michael-password`, `neededForUsers`)
     with sops. On thanatos sops reads its age key from /persist directly
     (`impermanence.nix` repoints `sops.age.keyFile`/`sshKeyPaths` there), so the
     key MUST already be on `/mnt/persist` or activation fails with "failed to
     decrypt" (switch-to-configuration exit 4). Seed it now, before Stage 8:
```
install -d -m0755 /mnt/persist/etc/ssh /mnt/persist/var/lib/sops-nix
cp -a /oldroot/etc/ssh/ssh_host_ed25519_key /oldroot/etc/ssh/ssh_host_ed25519_key.pub \
      /oldroot/etc/ssh/ssh_host_rsa_key     /oldroot/etc/ssh/ssh_host_rsa_key.pub \
      /mnt/persist/etc/ssh/
cp -a /oldroot/etc/machine-id     /mnt/persist/etc/machine-id
# trailing /. copies CONTENTS -- idempotent even if a prior failed attempt
# already created the dir (avoids nesting sops-nix/sops-nix)
cp -a /oldroot/var/lib/sops-nix/. /mnt/persist/var/lib/sops-nix/
# sanity: the age key that decrypts the login password is in place
ls -l /mnt/persist/var/lib/sops-nix/key.txt /mnt/persist/etc/ssh/ssh_host_ed25519_key
```

--------------------------------------------------------------------------------
## 8. INSTALL NIXOS  (builds/downloads the closure — needs network, takes time)
--------------------------------------------------------------------------------

```
nixos-install --root /mnt --flake /root/nix-config#thanatos --no-root-passwd
```
- PRECONDITION: Stage 7.2 must be done. If the sops age key is not yet on
  `/mnt/persist`, activation cannot decrypt the login password and the install
  aborts (switch-to-configuration exit 4).
- `--no-root-passwd`: users are declarative (login password comes from sops).
- If it warns about a dirty git tree (from a by-id edit), that is fine as long as
  you staged the edit in Stage 4.4.
- If it fails to find the lanzaboote keys, re-check Stage 7.1.
- Do NOT reboot yet — the rest of /persist and /home must be seeded first.

--------------------------------------------------------------------------------
## 9. SEED /persist AND COPY /home  (the boot-critical state)
--------------------------------------------------------------------------------

9.1  Remaining boot-critical state (ssh host keys, machine-id, and the sops age
     key were already seeded in Stage 7.2). uid/gid map, Secure Boot keys at
     their runtime bind path, ZeroTier id:
```
install -d -m0755 /mnt/persist/var/lib
cp -a /oldroot/var/lib/nixos        /mnt/persist/var/lib/
cp -a /oldroot/var/lib/sbctl        /mnt/persist/var/lib/
cp -a /oldroot/var/lib/zerotier-one /mnt/persist/var/lib/
```

9.2  Service state (skips anything absent on the old drive):
```
for p in \
  var/lib/NetworkManager var/lib/bluetooth var/lib/fprint var/lib/cups \
  var/lib/containers var/lib/libvirt var/lib/flatpak var/lib/syncthing \
  var/lib/waydroid etc/cups etc/windscribe etc/NetworkManager/system-connections
do
  if [ -e "/oldroot/$p" ]; then
    install -d "/mnt/persist/$(dirname "$p")"
    cp -a "/oldroot/$p" "/mnt/persist/$p"
  fi
done

# libvirt's at-rest secrets-encryption-key is HOST-SPECIFIC: a random key wrapped
# by systemd-creds against THIS host's /var/lib/systemd/credential.secret (+ TPM).
# Copying the old drive's copy orphans it (that credential.secret is not migrated),
# and libvirtd then fails at step CREDENTIALS (status=243/CREDENTIALS) on every
# boot. Drop it so libvirt's virt-secret-init-encryption.service (guarded by
# ConditionPathExists=!<key>) regenerates a fresh one for this host on first boot.
# NOTE: only safe because there are no libvirt <secret> objects to preserve. If
# /oldroot/var/lib/libvirt/secrets/ contains *.xml secret definitions, instead
# migrate /oldroot/var/lib/systemd/credential.secret so those values stay readable.
rm -f /mnt/persist/var/lib/libvirt/secrets/secrets-encryption-key
```

9.3  Verify the boot-critical seeds exist:
```
ls -l /mnt/persist/var/lib/sops-nix/key.txt \
      /mnt/persist/var/lib/zerotier-one/identity.secret \
      /mnt/persist/var/lib/sbctl \
      /mnt/persist/etc/ssh/ssh_host_ed25519_key \
      /mnt/persist/etc/machine-id
```

9.4  Copy /home (~154G). Throughput may drop mid-copy as the P310's SLC cache
     fills — that is normal:
```
rsync -aHAXS --info=progress2 /oldroot/home/ /mnt/home/
du -sh /oldroot/home /mnt/home   # sizes should be close
```

--------------------------------------------------------------------------------
## 10. BACK UP LUKS HEADERS  (do not skip — cheap disaster insurance)
--------------------------------------------------------------------------------

```
mkdir -p /root/luks-headers
cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-thanatos-swap   --header-backup-file /root/luks-headers/cryptswap.img
cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-thanatos-home   --header-backup-file /root/luks-headers/crypthome.img
cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-thanatos-system --header-backup-file /root/luks-headers/cryptsystem.img
```
Copy `/root/luks-headers/*.img` to a SEPARATE USB stick / external location now
(they are in RAM and will be lost on reboot). Without a header, a corrupted LUKS
header = unrecoverable data even with the passphrase.

--------------------------------------------------------------------------------
## 11. UNMOUNT, REBOOT, RE-ENABLE SECURE BOOT
--------------------------------------------------------------------------------

```
sync
umount -R /mnt
umount /oldroot && cryptsetup close oldroot
sync
```

11.1  Physically UNPLUG the old-drive enclosure (so there is zero ambiguity at
      first boot).

11.2  `reboot`. Remove the live USB during POST.

11.3  Enter firmware setup. RE-ENABLE Secure Boot. Set the internal NVMe first in
      boot order. Save + exit.

--------------------------------------------------------------------------------
## 12. FIRST BOOT — VERIFICATION GATES
--------------------------------------------------------------------------------

You should get ONE LUKS passphrase prompt, then a normal boot to the login/greeter.

12.1  Log in. If login works, sops decrypted your password -> the age key seed is
      correct.

12.2  Confirm the rollback ran and the root is ephemeral:
```
systemctl status rollback           # should show active (exited) [RemainAfterExit]
journalctl -b -u rollback
sudo touch /ephemeral-test          # then reboot and check it is gone (step 12.5)
```

12.3  Confirm boot-critical state carried over (compare to Stage 1.2):
```
sudo sbctl status                   # Secure Boot: enabled, keys installed
sudo bootctl status | grep -i secure
zerotier-cli info                   # SAME node id as Stage 1.2
nmcli -g NAME connection show       # your wifi/VPN connections present
fprintd-list "$USER"                # enrolled fingerprints present
```

12.4  Confirm the filesystem topology and isolation:
```
findmnt /home                       # backed by /dev/mapper/crypthome (separate fs)
findmnt / ; findmnt /nix ; findmnt /persist   # all on /dev/mapper/cryptsystem
sudo btrfs filesystem usage /
sudo btrfs filesystem usage /home
```

12.5  Prove the wipe: reboot once more, then:
```
ls /ephemeral-test                  # must be "No such file" — root was wiped
ls ~                                # your home is intact (separate persistent fs)
```

12.6  (Optional) Confirm hibernation:
```
systemctl hibernate                 # then power on and confirm the session resumes
```

If ALL gates pass, the migration is complete.

--------------------------------------------------------------------------------
## 13. POST-MIGRATION
--------------------------------------------------------------------------------

- Keep the OLD 512G drive as a LABELED cold spare. Do NOT wipe it until you have
  run several days of normal use on the new drive. It remains a full fallback
  (see Recovery).
- If anything "forgets" state across reboots (some app resets each boot), its
  data dir needs persisting: add the path to `directories`/`files` in
  `nixos/thanatos/impermanence.nix`, then
  `sudo nixos-rebuild switch --flake ~/nix-config#thanatos`, and commit.
- (Optional, deferred) FIDO2 auto-unlock: enroll a hardware key on each container
  and add `settings.crypttabExtraOpts = ["fido2-device=auto" "token-timeout=10"]`
  in disk-config.nix (as on kore/atlas), e.g.:
    `sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-partlabel/disk-thanatos-system`
  (repeat for -home and -swap), then rebuild.

--------------------------------------------------------------------------------
## 14. RECOVERY / ROLLBACK
--------------------------------------------------------------------------------

Your old drive is untouched. To return to it at any point:
- Power off, remove the new drive, re-install the OLD 512G drive in the M.2 slot,
  boot. It is your exact prior system (Secure Boot keys still enrolled). Done.
- If you want to REINSTALL the old layout from the repo instead:
  boot a live USB, and `nixos-install --root /mnt --flake <repo>#thanatos-legacy`
  after `disko`-ing the legacy config. Never use `.#thanatos` on the 512G drive.

--------------------------------------------------------------------------------
## 15. TROUBLESHOOTING (by symptom)
--------------------------------------------------------------------------------

- LOGIN FAILS on first boot (password rejected): sops could not decrypt. Boot the
  live USB, unlock cryptsystem, mount subvol=persist, and confirm
  `persist/var/lib/sops-nix/key.txt` and `persist/etc/ssh/ssh_host_ed25519_key`
  exist and match the old drive's. Re-seed if missing (Stage 9.1). Also check
  `journalctl -b | grep -i sops` on the failed boot.

- SECURE BOOT error / won't boot after re-enabling SB: your UKI signature is not
  trusted. Easiest: boot with SB disabled, then `sudo sbctl verify` and
  `sudo sbctl sign-all` / `sudo nixos-rebuild switch --flake ~/nix-config#thanatos`
  to re-sign with the enrolled keys, then re-enable SB. If keys were NOT reused,
  enroll: `sudo sbctl enroll-keys` (in firmware Setup Mode) then rebuild.

- ROLLBACK service failed / boot hangs in initrd: check the emergency shell.
  Confirm `root-blank` exists: unlock cryptsystem, `mount -o subvol=/ ... /mnt`,
  `btrfs subvolume list /mnt` should show `root-blank`. If missing, re-create it
  (Stage 6) from a fresh empty `root` (delete the populated one first).

- ZEROTIER shows a NEW node id (fell off networks): `/var/lib/zerotier-one` was
  not persisted correctly. Re-seed from the old drive (Stage 9.1) and re-authorize
  is not needed once the identity is restored.

- disko "device busy" / signatures: `wipefs -a /dev/nvme0n1`, ensure nothing is
  mounted from it, retry Stage 5.

- USB drops out mid-rsync (UAS resets): reboot live USB with
  `usb-storage.quirks=152d:0583:u`, re-mount old drive, re-run Stage 9.4 (rsync
  resumes/continues).

- by-id path not found during install: the disk-config `device` does not match
  the actual drive. Fix `nixos/thanatos/disk-config.nix`, `git add` it, re-run
  Stage 8 (disko in Stage 5 used the file directly and already formatted; you can
  re-run just `nixos-install`).
