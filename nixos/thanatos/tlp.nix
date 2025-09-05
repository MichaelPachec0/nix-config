{...}: {
  services.tlp = {
    enable = true;
    settings = {
      # RUNTIME_PM_DRIVER_DENYLIST = ""; # empty = no driver exceptions
      # Power mode: use battery settings by default
      # TLP_DEFAULT_MODE = "BAT";
      # TLP_PERSISTENT_DEFAULT = 1; # stick to battery mode

      # CPU: power-efficient governor and disable boost on battery
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";
      CPU_BOOST_ON_BAT = 0;
      CPU_BOOST_ON_AC = 1;

      # Disk: aggressive APM and faster spindown
      DISK_APM_LEVEL_ON_BAT = "128 128";
      DISK_SPINDOWN_TIMEOUT_ON_BAT = "120 120";
      # DISK_IOSCHED = "mq-deadline"; # fallback if supported

      # Radeon iGPU: lowest power levels
      # RADEON_POWER_PROFILE_ON_BAT = "low";
      RADEON_DPM_PERF_LEVEL_ON_BAT = "mid";

      RADEON_DPM_STATE_ON_BAT = "battery";
      # AMDGPU_ABM_LEVEL_ON_AC = 0;
      AMDGPU_ABM_LEVEL_ON_BAT = 3;

      # 04:00.0 Unassigned class [ff00]: Realtek Semiconductor Co., Ltd. RTS522A PCI Express Card Reader (rev 01)
      #         Subsystem: Lenovo Device 5082
      #         Control: I/O- Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr+ Stepping- SERR+ FastB2B- DisINTx+
      #         Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR+ <PERR- INTx-
      #         Latency: 0, Cache Line Size: 1020 bytes
      #         Interrupt: pin A routed to IRQ 38
      #         IOMMU group: 15
      #         Region 0: Memory at fd600000 (32-bit, non-prefetchable) [size=4K]
      #         Capabilities: [40] Power Management version 3
      #                 Flags: PMEClk- DSI- D1+ D2+ AuxCurrent=375mA PME(D0-,D1+,D2+,D3hot+,D3cold+)
      #                 Status: D0 NoSoftRst- PME-Enable- DSel=0 DScale=0 PME-
      #         Capabilities: [50] MSI: Enable+ Count=1/1 Maskable- 64bit+
      #                 Address: 00000000fee00000  Data: 0000
      #         Capabilities: [70] Express (v2) Endpoint, IntMsgNum 0
      #                 DevCap: MaxPayload 128 bytes, PhantFunc 0, Latency L0s unlimited, L1 unlimited
      #                         ExtTag- AttnBtn- AttnInd- PwrInd- RBE+ FLReset- SlotPowerLimit 0W TEE-IO-
      #                 DevCtl: CorrErr+ NonFatalErr+ FatalErr+ UnsupReq+
      #                         RlxdOrd+ ExtTag+ PhantFunc- AuxPwr+ NoSnoop-
      #                         MaxPayload 16384 bytes, MaxReadReq 16384 bytes
      #                 DevSta: CorrErr+ NonFatalErr+ FatalErr- UnsupReq+ AuxPwr+ TransPend-
      #                 LnkCap: Port #0, Speed 2.5GT/s, Width x1, ASPM L0s L1, Exit Latency L0s unlimited, L1 <64us
      #                         ClockPM+ Surprise- LLActRep- BwNot- ASPMOptComp+
      #                 LnkCtl: ASPM L1 Enabled; RCB 128 bytes, LnkDisable- CommClk+
      #                         ExtSynch+ ClockPM+ AutWidDis- BWInt- AutBWInt- FltModeDis-
      #                 LnkSta: Speed 2.5GT/s, Width x1
      #                         TrErr- Train- SlotClk+ DLActive- BWMgmt- ABWMgmt-
      #                 DevCap2: Completion Timeout: Not Supported, TimeoutDis+ NROPrPrP- LTR+
      #                         10BitTagComp- 10BitTagReq- OBFF Via message/WAKE#, ExtFmt- EETLPPrefix-
      #                         EmergencyPowerReduction Not Supported, EmergencyPowerReductionInit-
      #                         FRS- TPHComp- ExtTPHComp-
      #                         AtomicOpsCap: 32bit- 64bit- 128bitCAS-
      #                 DevCtl2: Completion Timeout: 50us to 50ms, TimeoutDis+
      #                         AtomicOpsCtl: ReqEn-
      #                         IDOReq- IDOCompl- LTR+ EmergencyPowerReductionReq-
      #                         10BitTagReq- OBFF Via WAKE#, EETLPPrefixBlk-
      #                 LnkCtl2: Target Link Speed: Unknown, EnterCompliance+ SpeedDis+
      #                         Transmit Margin: Unknown, EnterModifiedCompliance+ ComplianceSOS+
      #                         Compliance Preset/De-emphasis: Unknown
      #                 LnkSta2: Current De-emphasis Level: -3.5dB, EqualizationComplete- EqualizationPhase1-
      #                         EqualizationPhase2- EqualizationPhase3- LinkEqualizationRequest-
      #                         Retimer- 2Retimers- CrosslinkRes: unsupported, FltMode-
      #         Capabilities: [100 v2] Advanced Error Reporting
      #                 UESta:  DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP-
      #                         ECRC- UnsupReq+ ACSViol- UncorrIntErr- BlockedTLP- AtomicOpBlocked- TLPBlockedErr-
      #                         PoisonTLPBlocked- DMWrReqBlocked- IDECheck- MisIDETLP- PCRC_CHECK- TLPXlatBlocked-
      #                 UEMsk:  DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP-
      #                         ECRC- UnsupReq- ACSViol- UncorrIntErr+ BlockedTLP- AtomicOpBlocked- TLPBlockedErr-
      #                         PoisonTLPBlocked- DMWrReqBlocked- IDECheck- MisIDETLP- PCRC_CHECK- TLPXlatBlocked-
      #                 UESvrt: DLP+ SDES+ TLP- FCP+ CmpltTO- CmpltAbrt- UnxCmplt- RxOF+ MalfTLP+
      #                         ECRC- UnsupReq- ACSViol- UncorrIntErr+ BlockedTLP- AtomicOpBlocked- TLPBlockedErr-
      #                         PoisonTLPBlocked- DMWrReqBlocked- IDECheck- MisIDETLP- PCRC_CHECK- TLPXlatBlocked-
      #                 CESta:  RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr+ CorrIntErr- HeaderOF-
      #                 CEMsk:  RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr+ CorrIntErr+ HeaderOF-
      #                 AERCap: First Error Pointer: 14, ECRCGenCap+ ECRCGenEn- ECRCChkCap+ ECRCChkEn-
      #                         MultHdrRecCap- MultHdrRecEn- TLPPfxPres- HdrLogCap-
      #                 HeaderLog: 40001001 0000000f fd600010 00000000
      #         Capabilities: [140 v1] Device Serial Number 00-00-00-01-00-4c-e0-00
      #         Capabilities: [150 v1] Latency Tolerance Reporting
      #                 Max snoop latency: 1048576ns
      #                 Max no snoop latency: 1048576ns
      #         Capabilities: [158 v1] L1 PM Substates
      #                 L1SubCap: PCI-PM_L1.2+ PCI-PM_L1.1+ ASPM_L1.2+ ASPM_L1.1+ L1_PM_Substates+
      #                          PortCommonModeRestoreTime=60us PortTPowerOnTime=60us
      #                 L1SubCtl1: PCI-PM_L1.2- PCI-PM_L1.1- ASPM_L1.2- ASPM_L1.1-
      #                           T_CommonMode=0us LTR1.2_Threshold=<error>
      #                 L1SubCtl2: T_PwrOn=<error>
      #         Kernel driver in use: rtsx_pci
      #         Kernel modules: rtsx_pci
      # PCIe power management
      # PCIE_ASPM_ON_BAT = "powersave"; # might be too agressive, some devices wont come back from this
      PCIE_ASPM_ON_BAT = "powersupersave"; # might be too agressive, some devices wont come back from this
      # PCIE_ASPM_ON_AC = "powersave";
      RUNTIME_PM_DENYLIST = "04:00.0 00:02.4";
      RUNTIME_PM_DRIVER_DENYLIST="rtsx_pci";
      # PCIE_ASPM_ON_AC = "powersupersave";

      # Runtime PM for PCI devices
      RUNTIME_PM_ON_BAT = "on";
      RUNTIME_PM_ON_AC = "on";
      # RUNTIME_PM_ON_AC = "auto";

      # USB autosuspend
      USB_AUTOSUSPEND = 1;
      USB_BLACKLIST_BTUSB = 0; # allow Bluetooth to suspend

      # Sound: power saving enabled
      SOUND_POWER_SAVE_ON_BAT = 1;
      SOUND_POWER_SAVE_CONTROLLER = 1;

      # Wi-Fi power save
      WIFI_PWR_ON_BAT = "on";

      # Disable hardware when on battery
      # DEVICES_TO_DISABLE_ON_BAT = ["bluetooth" "wwan"];
      # DEVICES_TO_ENABLE_ON_AC = ["bluetooth"];

      # Disable noisy NMI watchdog
      NMI_WATCHDOG = 0;

      # Battery charge thresholds (if supported)
      START_CHARGE_THRESH_BAT0 = 60;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
    # settings = {
    #   # Default power mode (can be overridden by AC/BAT state)
    #   TLP_DEFAULT_MODE = "AC";
    #   TLP_PERSISTENT_DEFAULT = 1;
    #
    #   ###################
    #   # CPU GOVERNORS
    #   ###################
    #   CPU_SCALING_GOVERNOR_ON_AC = "performance";
    #   CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
    #
    #   CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
    #   # CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
    #
    #   CPU_MIN_PERF_ON_AC = 0;
    #   CPU_MAX_PERF_ON_AC = 100;
    #   CPU_MIN_PERF_ON_BAT = 0;
    #   CPU_MAX_PERF_ON_BAT = 30;
    #
    #   AMD_CPU_BOOST_ON_AC = 1;
    #   AMD_CPU_BOOST_ON_BAT = 0;
    #
    #   #####################
    #   # PCIe Runtime Power
    #   #####################
    #   RUNTIME_PM_ON_AC = "on";
    #   RUNTIME_PM_ON_BAT = "auto";
    #
    #   PCIE_ASPM_ON_AC = "default";
    #   PCIE_ASPM_ON_BAT = "powersupersave";
    #
    #   #################
    #   # USB AUTOSUSPEND
    #   #################
    #   USB_AUTOSUSPEND = 1;
    #   USB_BLACKLIST_BTUSB = 0;
    #   USB_ALLOWLIST = "";
    #
    #   ##################
    #   # AUDIO & BLUETOOTH
    #   ##################
    #   SOUND_POWER_SAVE_ON_AC = 1;
    #   SOUND_POWER_SAVE_ON_BAT = 10;
    #
    #   WIFI_PWR_ON_AC = "off";
    #   WIFI_PWR_ON_BAT = "on";
    #
    #   BT_POWER_ON_AC = 1;
    #   BT_POWER_ON_BAT = 0;
    #
    #   #################
    #   # THINKPAD-SPECIFIC
    #   #################
    #   NATACPI_ENABLE = 1;
    #   TPACPI_ENABLE = 1;
    #   TPACPI_IGNORE_BIOS = 1;
    #
    #   START_CHARGE_THRESH_BAT0 = 50;
    #   STOP_CHARGE_THRESH_BAT0 = 80;
    #
    #   #################
    #   # DISK SETTINGS
    #   #################
    #   DISK_APM_LEVEL_ON_AC = "254 254";
    #   DISK_APM_LEVEL_ON_BAT = "128 128";
    #
    #   SATA_LINKPWR_ON_AC = "max_performance";
    #   SATA_LINKPWR_ON_BAT = "min_power";
    #
    #   #######################
    #   # GPU (RADEON/AMDGPU)
    #   #######################
    #   # RADEON_POWER_PROFILE_ON_AC = "high";
    #   # RADEON_POWER_PROFILE_ON_BAT = "low";
    #   # RADEON_DPM_PERF_LEVEL_ON_AC = "auto";
    #   # RADEON_DPM_PERF_LEVEL_ON_BAT = "low";
    #
    #   # Uncomment if you use amdgpu instead of radeon:
    #   AMDGPU_DPM_PERF_LEVEL_ON_AC = "auto";
    #   AMDGPU_DPM_PERF_LEVEL_ON_BAT = "low";
    #
    #   #################
    #   # MISC
    #   #################
    #   RESTORE_DEVICE_STATE_ON_STARTUP = 1;
    #   TLP_STATS = 1;
    # };
  };

  # Optional: If you're using amd_pstate, include this in your boot kernel params
  # boot.kernelParams = ["amd_pstate=active"];

  # Optional: enable CPU frequency scaling frontend
  # powerManagement.cpuFreqGovernor = "performance"; # fallback
}
