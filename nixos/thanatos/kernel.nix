# TEMPORARY host override for the staged CachyOS kernel rollout.
#
# thanatos goes first because its out-of-tree modules are two small ones
# (ryzen-smu, zenpower, see amd.nix). nyx carries nvidia, a far larger
# compatibility surface, so proving the kernel here means a later nyx failure is
# attributable to nvidia rather than to the kernel swap. Once nyx is on the same
# kernel this file is deleted and the value moves to the shared nyx/boot.nix.
{pkgs, ...}: {
  # x86_64-v3, not v4 and not zen4. This is a Zen 2 part: it has AVX2 (which v3
  # requires) and does not have AVX-512 (which v4 requires), so a v4 kernel
  # would fault on its first optimised instruction. Checked against
  # /proc/cpuinfo flags rather than against the marketing name -- avx2 present,
  # avx512f absent. Re-check that before changing the tier, not the model
  # number.
  #
  # -lto. The upstream flake already runs helpers.kernelModuleLLVMOverride over
  # every linuxPackages-* set it exports, but that helper only rewrites a
  # literal `gcc` inside a module's own Makefile, and neither of this host's two
  # out-of-tree modules has one. See the toolchain fix next to
  # boot.extraModulePackages in amd.nix -- without it zenpower fails to build.
  #
  # `bore`, and now a decision rather than a test. Measured by
  # ab-matrix/sched-ab.sh across three arms in one boot -- scx_flash,
  # EEVDF+BORE, EEVDF alone -- over 38 cells and 12 complete repetitions.
  # Against plain EEVDF on this same kernel, BORE cut wakeup p99 from 597us to
  # 377us and wakeup p99.9 from 1809us to 1220us, both resolvable by a wide
  # margin. scx_flash was then switched off in memory.nix on the strength of
  # the same run; the numbers and the honest limits of that call live next to
  # services.scx there.
  #
  # This variant is therefore load-bearing, not exploratory: memory.nix sets
  # kernel.sched_bore=1 and would be configuring a sysctl that does not exist
  # if this were reverted to linuxPackages-cachyos-latest-lto-x86_64-v3.
  #
  # TRAP: `uname -r` reports 7.1.8-cachyos-lto for BOTH this and the non-bore
  # build, so it cannot tell you which one is running. Use
  # `readlink -f /run/booted-system/kernel`, or check whether
  # /proc/sys/kernel/sched_bore exists.
  kernel.mod.kernelPkg = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
}
