{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # device = "/dev/sda";
        device = "/dev/disk/by-path/pci-0000:18:00.0-scsi-0:0:0:1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "2G";
              type = "EF00";
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
                type = "swap";
                randomEncryption = true;
              };
            };
            root = {
              end = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-f"]; # Override existing partition
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted
                subvolumes = {
                  # Subvolume name is different from mountpoint
                  "/rootfs" = {
                    mountOptions = ["compress=zstd" "noatime"];
                    mountpoint = "/";
                  };
                  # Subvolume name is the same as the mountpoint
                  "/home" = {
                    mountOptions = ["compress=zstd" "noatime"];
                    mountpoint = "/home";
                  };
                  # Parent is not mounted so the mountpoint must be set
                  "/nix" = {
                    mountOptions = ["compress=zstd" "noatime"];
                    mountpoint = "/nix";
                  };
                  # This subvolume will be created but not mounted
                  "/persist" = {
                    mountOptions = ["compress=zstd" "noatime"];
                    mountpoint = "/persist";
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
