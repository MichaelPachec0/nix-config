# Boot counting (Automatic Boot Assessment) for hosts on nixos-26.05.
#
# Stable's systemd-boot module has no bootCounting option; the vendored copy
# next to this file (nixpkgs unstable rev e72e4f29) does. It is byte-exact
# with upstream so a later diff stays clean. Every external option it reads
# (boot.loader.efi, boot.loader.timeout, hardware.deviceTree, systemd.package,
# nix.package, system.nixos, boot.kernelPackages.kernel.features) exists on
# 26.05, and stable's systemd.nix already installs systemd-bless-boot.service
# and boot-complete.target. The builder's `preferred` loader key needs
# systemd-boot >= 260; stable ships 260.2.
#
# How it behaves once enabled:
# - only generations written after enablement get a counter (+2); entries
#   already on the ESP keep their counter-less, i.e. good, names;
# - loader.conf gets `preferred <current>` plus `default nixos-*`; sd-boot
#   sorts exhausted entries last, so the glob resolves to the newest entry
#   that is not bad. That is the fallback;
# - no EFI variables are touched; bless-boot renames files on the ESP.
#
# Sunset: the warning below fires as soon as the stable module this file
# disables contains "bootCounting". Then delete this directory, drop the
# import from the hosts, and keep the bootCounting settings.
{
  lib,
  modulesPath,
  ...
}: let
  stableModule = "${modulesPath}/system/boot/loader/systemd-boot/systemd-boot.nix";
  stableHasIt = lib.hasInfix "bootCounting" (builtins.readFile stableModule);
in {
  disabledModules = ["system/boot/loader/systemd-boot/systemd-boot.nix"];
  imports = [./systemd-boot.nix];

  boot.loader.systemd-boot.bootCounting = {
    enable = true;
    # Two tries at 15 minutes each bound the worst case near 35 minutes.
    tries = 2;
  };

  warnings = lib.optional stableHasIt ''
    features/nixos/server/boot-counting: nixpkgs-stable now ships
    boot.loader.systemd-boot.bootCounting. Drop the vendored systemd-boot
    module (delete the directory, remove the import, keep the settings).
  '';
}
