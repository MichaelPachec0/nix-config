{
  disko.devices = {
    disk.thanatos = {
      # Crucial P310 2TB. VERIFY this path once slotted internally:
      #   ls /dev/disk/by-id/nvme-*
      device = "/dev/disk/by-id/nvme-CT2000P310SSD8_2530519CAA98";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "4G";
            type = "EF00"; # EFI System Partition (lanzaboote UKIs)
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          swap = {
            size = "48G";
            content = {
              type = "luks";
              name = "cryptswap";
              settings.allowDiscards = true;
              content = {
                type = "swap";
                resumeDevice = true; # hibernation
              };
            };
          };

          home = {
            size = "1024G";
            content = {
              type = "luks";
              name = "crypthome";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = [ "-L" "home" "-f" ];
                subvolumes = {
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = [ "subvol=home" "compress=zstd" "noatime" ];
                  };
                };
              };
            };
          };

          system = {
            size = "100%"; # remainder
            content = {
              type = "luks";
              name = "cryptsystem";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = [ "-L" "nixos" "-f" ];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [ "subvol=root" "compress=zstd" "noatime" ];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "subvol=nix" "compress=zstd" "noatime" ];
                  };
                  "/persist" = {
                    # NOT noexec: impermanence bind-mounts executable state
                    # (e.g. /var/lib/flatpak) out of here.
                    mountpoint = "/persist";
                    mountOptions = [ "subvol=persist" "compress=zstd" "noatime" ];
                  };
                  "/log" = {
                    mountpoint = "/var/log";
                    mountOptions = [ "subvol=log" "compress=zstd" "noatime" "noexec" ];
                  };
                  "/tmp" = {
                    # NOT noexec: nix builds exec in /tmp.
                    mountpoint = "/tmp";
                    mountOptions = [ "subvol=tmp" "compress=zstd" "noatime" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
