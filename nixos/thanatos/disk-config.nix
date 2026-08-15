# compress-force=zstd:1 on every subvolume.
#
# zstd was measured against lzo and zlib on 171 MiB of real store bytes and
# dominates both: zlib has a worse ratio AND 2.1x the read latency, and lzo's
# faster decompression is exactly cancelled by reading a 27% bigger file.
# Level 1 rather than the previous 3 because levels 1/3/9 come out
# byte-identical on disk with read latencies inside noise, so 1 is free
# throughput -- btrfs compresses in independent 128 KiB chunks with no shared
# history, which is precisely what high zstd levels trade compute for.
#
# compress-force rather than plain compress because btrfs's file-level
# heuristic abandons a whole inode when compressing its first portion fails,
# which misfires on ~6% of the closure (Chromium/Slack .pak bundles open with
# an incompressible index and then compress to 0.22). zstd already decides per
# block and falls back to raw for anything that grows, so the file-level rule
# only adds false negatives. Cost of that choice: those files used to read at
# ~88 us instead of ~358 us precisely because they were stored raw.
#
# Compression is the largest single cost on the cold read path -- a 4K fault
# against /nix pulls and decompresses a whole 128K extent, ~600 us versus ~100
# us uncompressed. It stays anyway, and do NOT propose dropping or lowering it
# as a latency fix: a cold Firefox launch is only ~150 ms slower than a warm
# one out of ~1.4 s, so this can account for a fraction of that at most, in
# exchange for rewriting the whole store.
#
# Nor is there anything to gain from rewriting existing data at the new level:
# zstd:1 and zstd:3 measured byte-identical, so a recursive defragment rewrites
# 118 GiB on a DRAM-less QLC drive to recover nothing. The mount option applies
# to new writes and the store converges on its own.
#
# Anyone re-benchmarking this: st_blocks on btrfs reports LOGICAL size and will
# show ratio 1.000 for every arm, and timing a buffered write plus fsync
# measures device commit rather than compression (writeback compresses in
# parallel kernel workers, which produced write speed RISING with zstd level).
# Verify the compressed-extent fraction via FIEMAP before believing any row.
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
              mountOptions = ["umask=0077"];
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
                extraArgs = ["-L" "home" "-f"];
                subvolumes = {
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = ["subvol=home" "compress-force=zstd:1" "noatime"];
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
                extraArgs = ["-L" "nixos" "-f"];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = ["subvol=root" "compress-force=zstd:1" "noatime"];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["subvol=nix" "compress-force=zstd:1" "noatime"];
                  };
                  "/persist" = {
                    # NOT noexec: impermanence bind-mounts executable state
                    # (e.g. /var/lib/flatpak) out of here.
                    mountpoint = "/persist";
                    mountOptions = ["subvol=persist" "compress-force=zstd:1" "noatime"];
                  };
                  "/log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["subvol=log" "compress-force=zstd:1" "noatime" "noexec"];
                  };
                  "/tmp" = {
                    # NOT noexec: nix builds exec in /tmp.
                    mountpoint = "/tmp";
                    mountOptions = ["subvol=tmp" "compress-force=zstd:1" "noatime"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Decrypt in the completion context instead of handing every bio to the
  # kcryptd workqueue: submit -> NVMe -> IRQ completion -> queue work -> wake a
  # kworker -> schedule it -> decrypt -> endio. That extra wakeup was free
  # against a disk seek and is not against an NVMe answering in ~100 us. The
  # trade is that decryption then runs in softirq on the completing CPU (~49%
  # of one core during a single-stream read) instead of spreading over
  # kworkers, which is wrong for a CPU without AES acceleration or for
  # saturating many drives, and right for one NVMe on a part with AES-NI.
  #
  # THESE SETTINGS ARE INERT HERE and are set true only so the config states
  # what is actually true of the running system, and so the behaviour survives
  # a move off this kernel. linux-xanmod carries a ZEN patch that disables the
  # dm-crypt workqueues outright: a throwaway LUKS2 device opened with no
  # --perf-* options and no header flags still comes up with
  # no_read_workqueue no_write_workqueue in its live table. The option can
  # therefore only ever turn the bypass ON, never off. Check the real state
  # with `dmsetup table cryptsystem`, never by reading this file.
  #
  # No valid measurement of this flag exists for this machine, and two rounds of
  # numbers that used to live here were deleted rather than corrected: both
  # toggled arms with `cryptsetup refresh`, which cannot clear the flags on this
  # kernel, so both arms measured the same thing. An A/B needs a kernel built
  # without the ZEN patch and is not reachable from Nix config alone. It would
  # also need both arms in one batch plus an O_DIRECT control against the raw
  # device: this drive's baseline moved ~2x within an hour on an unchanged
  # system, cause never identified, so any comparison spanning a reboot is
  # meaningless on its own.
  #
  # nyx's atlas and kore set the equivalent through disko's extraOpenArgs, which
  # feeds disko's own format/mount scripts; the boot-time unlock is generated
  # separately, so the option below is what reaches cryptsetup here. Those hosts
  # run a different kernel, so there the setting is not inert.
  boot.initrd.luks.devices = {
    cryptsystem.bypassWorkqueues = true;
    crypthome.bypassWorkqueues = true;
    cryptswap.bypassWorkqueues = true;
  };
}
