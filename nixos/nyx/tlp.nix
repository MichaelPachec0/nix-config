{ ... }: {
  services.tlp = {
    enable = true;
    settings = {
      TLP_ENABLE = 1;
      TLP_DEFAULT_MODE = "AC";
      # Change by sensing powerstate
      TLP_PERSISTENT_DEFAULT = 0;
      # disk settings
      DISK_IDLE_SECS_ON_AC = 0;
      DISK_IDLE_SECS_ON_BAT = 2;
      #MAX_LOST_WORK_SECS_ON_AC = 15;
      #MAX_LOST_WORK_SECS_ON_BAT = 60;
      # cpu gov should already be done by the initial config
      #HWP
      CPU_HWP_ON_AC = "balance_performance";
      CPU_HWP_ON_BAT = "balance_power";
      # P-state stuff, might comment out
      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      #CPU_MIN_PERF_ON_BAT = 0;
      #CPU_MAX_PERF_ON_BAT = 50;
      # Turbo boost
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;
      CPU_HWP_DYN_BOOST_ON_AC = 1;
      CPU_HWP_DYN_BOOST_ON_BAT = 0;
      #coalesce work so cores sleep more
      SCHED_POWERSAVE_ON_AC = 0;
      SCHED_POWERSAVE_ON_BAT = 1;

      NMI_WATCHDOG = 0;

      ENERGY_PERF_POLICY_ON_AC = "performance";
      ENERGY_PERF_POLICY_ON_BAT = "power";

      DISK_DEVICES = "nvme-ADATA_SX8200PNP_2K3729A528XF";

      # apm level, disable for now
      #DISK_APM_LEVEL_ON_AC = "254";
      #DISK_APM_LEVEL_ON_BAT = "128;

      #IO Scheduler
      DISK_IOSCHED = "kyber";
      SATA_LINKPWR_ON_AC = "medium_power";
      #SATA_LINKPWR_ON_BAT = "min_power";
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
      AHCI_RUNTIME_PM_ON_AC = "on";
      AHCI_RUNTIME_PM_ON_BAT = "auto";

      # Wifi powersave
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # WOL
      WOL_DISABLE = "Y";

      # Audio Powersave
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;

      # Audio Controller
      SOUND_POWER_SAVE_CONTROLLER = "Y";

      # Runtime PCI-E PM
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      RUNTIME_PM_DISABLE = "00:1d.6 24:00.0 07:02.0 07:01.0 07:00.0 06:00.0";
      PCIE_ASPM_ON_AC = "performance";
      PCIE_ASPM_ON_BAT = "powersupersave";

      USB_AUTOSUSPEND = 1;

      # Need to make sure that both yubikey and logitech mouse are enumerated here
      # 046d:c52b - logitech unifiying receiver
      # 1050:0407 - Yubikey

      USB_DENYLIST = "046d:c52b 1050:0407";

      # Include bluetooth in usb powersave
      USB_BLACKLIST_BTUSB = 1;

      # enable phone charging
      USB_BLACKLIST_PHONE = 1;

      # include fingerprint and touch screen in usb autosuspend
      # 138a:0091 - fingerprint sensor
      # 04f3:24a0 - touch screen (ELAN)
      # 05ac:828d - Apple bluetooth host controller
      # 0c45:6713 - Webcam

      USB_ALLOWLIST = "138a:0091 04f3:24a0 05ac:828d  0c45:6713 05ac:4500 ";

      # suspend usb devices on shutdown
      # USB_AUTOSUSPEND_DISABLE_ON_SHUTDOWN = 1;

    };
  };
}
