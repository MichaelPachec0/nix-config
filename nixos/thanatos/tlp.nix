# TLP power policy for thanatos (ThinkPad P14s Gen 1, Ryzen 7 PRO 4750U).
#
# Every setting here was checked against this hardware with `tlp-stat` and the
# corresponding sysfs attribute; knobs that TLP accepts but that have nowhere to
# land on Renoir were removed rather than left as decoration. The removals are
# recorded in the comments below so they do not get re-added from a generic
# ThinkPad guide.
{...}: {
  services.tlp = {
    enable = true;
    settings = {
      # ---- CPU ------------------------------------------------------------
      # Deliberately conservative on battery: runtime hours are the goal and
      # on-battery responsiveness is explicitly not. acpi-cpufreq exposes only
      # three P-states (1.7 / 1.6 / 1.4 GHz) and its `powersave` governor pins
      # the lowest one, so battery runs at 1.4 GHz. That is intended.
      #
      # amd_pstate is NOT usable here and must not be re-proposed: this Zen2
      # Renoir part has no `cppc` flag, so the driver never binds and the
      # kernel parameter is a no-op (see nixos/thanatos/gaming.nix).
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # `tlp-stat -p` annotates this "(CPU not supported)", but the value
      # demonstrably lands anyway: checked live, boost reads 1 with AC plugged
      # in and 0 on battery, matching CPU_BOOST_ON_AC/CPU_BOOST_ON_BAT below --
      # so TLP IS driving this knob despite the "not supported" annotation. It
      # is kept because the kernel default is boost-enabled, and re-enabling
      # boost on battery is the opposite of what this file is for. Verify
      # after any change that /sys/devices/system/cpu/cpufreq/boost still
      # reads 0 ON BATTERY specifically -- it is expected to read 1 on AC.
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      # REMOVED: CPU_ENERGY_PERF_POLICY_ON_{AC,BAT}. Needs an
      # energy_performance_preference attribute; acpi-cpufreq exposes none, so
      # both values were silently discarded.

      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # ---- PCIe / runtime PM ----------------------------------------------
      # THE important setting in this file. TLP's "on" means "hold the device
      # powered"; "auto" means "may runtime-suspend". This read "on" on battery,
      # i.e. runtime PM was disabled exactly when it was wanted, and every PCI
      # device sat at power/control=on, runtime_status=active.
      #
      # It matters out of proportion to the devices themselves: a device held in
      # D0 keeps its parent bridge and root port awake, which blocks the SoC
      # from reaching deep package C-states. One un-suspended device taxes the
      # whole platform.
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      # Empty string, NOT omission. Leaving this key out does not mean "no
      # driver denylist" -- TLP falls back to the baseline baked into
      # share/tlp/defaults.conf, which is
      #   "mei_me nouveau radeon xhci_hcd"
      # and would pin BOTH onboard USB 3.1 controllers (07:00.3 and 07:00.4,
      # driver xhci_hcd) at control=on forever. Those two sit under bridge
      # 00:08.1 together with the GPU, HDMI audio, the PSP and HD audio, and a
      # bridge only suspends once every child is idle -- so the stock default
      # would hold that entire root port awake and defeat the setting above.
      # "" is TLP's documented way to disable the driver denylist completely.
      #
      # Trade-off accepted deliberately: xhci_hcd is in TLP's default list
      # because USB controller runtime PM has a history of wake regressions.
      # If USB wake or a specific device misbehaves, restore the stock list
      # rather than reverting RUNTIME_PM_ON_BAT.
      RUNTIME_PM_DRIVER_DENYLIST = "";

      # No address denylist either. The previous RUNTIME_PM_DENYLIST
      # "04:00.0 00:02.4" named ONE device twice over: 00:02.4 is a GPP bridge
      # whose only child is 04:00.0, the Realtek RTS522A card reader. The NVMe
      # hangs off a different root port (00:02.1 -> 01:00.0), so an aggressive
      # policy cannot wedge storage; the worst case is a card needing a replug.
      # If the reader does misbehave, re-add:
      #   RUNTIME_PM_DENYLIST = "04:00.0 00:02.4";

      # ---- PCIe ASPM ------------------------------------------------------
      # "default" is byte-identical to TLP's own stock default for AC; stated
      # explicitly (rather than omitted) so the AC/BAT pair reads symmetrically
      # next to each other, matching how the rest of this file always states
      # both sides.
      PCIE_ASPM_ON_AC = "default";
      PCIE_ASPM_ON_BAT = "powersupersave";

      # ---- USB ------------------------------------------------------------
      # USB_EXCLUDE_BTUSB is the TLP 1.9 name; USB_BLACKLIST_BTUSB is a
      # deprecated alias. 0 = do not exclude, i.e. Bluetooth may autosuspend.
      # If a YubiKey or the KM003C meter starts dropping out once runtime PM is
      # aggressive, add its VID:PID to USB_DENYLIST rather than turning
      # USB_AUTOSUSPEND off wholesale.
      USB_AUTOSUSPEND = 1;
      USB_EXCLUDE_BTUSB = 0;

      # ---- Radio / audio ---------------------------------------------------
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
      # 0 on AC deviates from TLP's own default of 1. This is NOT a power
      # optimisation -- it costs a little AC draw, not saves it -- it avoids
      # the audible HDA codec resume pop when the codec is woken from
      # power-save while plugged in. On battery the pop is an acceptable
      # trade for the power saved.
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;
      SOUND_POWER_SAVE_CONTROLLER = 1;

      # ---- Panel ------------------------------------------------------------
      # Adaptive Backlight Management. The panel is the single largest consumer
      # left on this machine, so this is the one graphics knob here that is not
      # decoration.
      #
      # This was briefly removed on the strength of a BAD PROBE: a
      # `find /sys -name panel_power_savings` without -L, which silently never
      # traversed /sys/class/drm/card1-eDP-1 because that is a symlink, and so
      # reported the attribute as absent. It is not. The real path is
      #   /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings
      # and it is writable. Verify with `find -L`, or just cat that path -- do
      # not re-derive this with a bare `find`.
      #
      # Levels are 0 (off) to 4 (most aggressive). ABM dims the backlight and
      # compensates in the pixel pipeline, so higher levels trade colour
      # accuracy and visible shifts on gradients for power. 3 is the level TLP
      # documents as a strong-but-usable default; drop to 1-2 if the shifting is
      # distracting on photos or video. AC is left at 0: there is no reason to
      # pay the image-quality cost while plugged in.
      AMDGPU_ABM_LEVEL_ON_AC = 0;
      AMDGPU_ABM_LEVEL_ON_BAT = 3;

      # ---- Misc ------------------------------------------------------------
      NMI_WATCHDOG = 0;

      # Charge thresholds. NOTE the tension: capping at 80% removes a fifth of
      # usable capacity and so costs more runtime than everything else in this
      # file recovers. It is kept anyway, as a deliberate trade of runtime for
      # calendar life on a 2020 pack. Raising STOP to 90/100 is the single
      # fastest way to get hours back if that trade is ever revisited.
      START_CHARGE_THRESH_BAT0 = 60;
      STOP_CHARGE_THRESH_BAT0 = 80;

      # REMOVED, all verified to do nothing on this machine:
      #   DISK_APM_LEVEL_ON_BAT, DISK_SPINDOWN_TIMEOUT_ON_BAT
      #     ATA-only; this host is NVMe-only. The NVMe already runtime-suspends
      #     (power/control=auto) with a 100 ms latency tolerance permitting deep
      #     APST states, which TLP is not involved in.
      #   RADEON_DPM_PERF_LEVEL_ON_BAT, RADEON_DPM_STATE_ON_BAT
      #     `tlp-stat -g` returns an empty graphics section and
      #     power_dpm_force_performance_level still read `auto` on battery.
      #     Additionally, the old setting was "mid", which is not in TLP's valid
      #     domain (auto|low|high), so it may have been rejected as invalid.
      # (AMDGPU_ABM_LEVEL_ON_BAT was listed here as inert. That was wrong -- see
      # the Panel section above. It is back, and it is real.)
    };
  };
}
