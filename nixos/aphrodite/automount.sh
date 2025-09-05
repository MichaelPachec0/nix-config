ENC="nixos"

mount -o subvol=root,compress=zstd,noatime /dev/mapper/$ENC /mnt


mount -o subvol=home,compress=zstd,noatime /dev/mapper/$ENC /mnt/home


mount -o subvol=nix,compress=zstd,noatime /dev/mapper/$ENC /mnt/nix


mount -o subvol=persist,compress=zstd,noatime /dev/mapper/$ENC /mnt/persist


mount -o subvol=log,compress=zstd,noatime /dev/mapper/$ENC /mnt/var/log
