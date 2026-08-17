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
  # Non-LTO on purpose. The -lto variants need the upstream flake's
  # helpers.kernelModuleLLVMOverride wrapped around the whole package set before
  # out-of-tree modules will compile, and this host has two of them. That is a
  # second failure surface for a gain nobody has measured yet; it can be a
  # separate, measured change later.
  #
  # `latest` rather than `bore`. sched_ext replaces the fair class wholesale
  # while scx_flash is attached (see memory.nix), so the built-in scheduler only
  # governs the window where scx is down. That window is real -- the attach race
  # documented there loses several attempts per boot -- but it is not where a
  # scheduler choice earns its keep, and picking `bore` would change the
  # variable under test for no measured reason.
  kernel.mod.kernelPkg = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;
}
