{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SHGS31-1000GS-2_FN0BN93251060BT4C";
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
                mountOptions = ["umask=0077"];
              };
            };
            swap = {
              size = "128G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            luks = {
              size = "100%";
              label = "luks";
              content = {
                type = "luks";
                name = "cryptroot";
                extraOpenArgs = [
                  "--allow-discards"
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                ];
                # https://0pointer.net/blog/unlocking-luks2-volumes-with-tpm2-fido2-pkcs11-security-hardware-on-systemd-248.html
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = ["fido2-device=auto" "token-timeout=10"];
                };
                content = {
                  type = "btrfs";
                  extraArgs = ["-L" "nixos" "-f"];
                  subvolumes = {
                    "/rootfs" = {
                      mountpoint = "/";
                      mountOptions = ["subvol=root" "compress=zstd" "noatime" ];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                    };
                    "/persist" = {
                      mountpoint = "/persist";
                      mountOptions = ["subvol=persist" "compress=zstd" "noatime" "noexec"];
                    };
                    "/log" = {
                      mountpoint = "/var/log";
                      mountOptions = ["subvol=log" "compress=zstd" "noatime" "noexec"];
                    };
                    # NOTE: tmp cannot be noexec
                    # ref: https://github.com/NixOS/nix/issues/157
                    "/tmp" = {
                      mountpoint = "/tmp";
                      mountOptions = ["subvol=log" "compress=zstd" "noatime"];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
}
