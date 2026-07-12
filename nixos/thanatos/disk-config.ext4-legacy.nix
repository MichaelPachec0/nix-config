{
  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-Micron_MTFDHBA512TDV_21042CF4DA27";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1G";
            type = "EF00"; # EFI System Partition
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          swap = {
            size = "24G";
            content = {
              type = "luks";
              name = "cryptswap";
              settings.allowDiscards = true;
              content = {
                type = "swap";
                resumeDevice = true; # Enable hibernation support
              };
            };
          };

          root = {
            size = "100%"; # Use remaining space
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}

  # fileSystems."/persist".neededForBoot = true;
  # fileSystems."/var/log".neededForBoot = true;
