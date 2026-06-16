{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
} @ args: let
  yubikey-manager = pkgs.yubikey-manager;
  # NOTE: This is not needed anymore. This is for compat reasons.
  thermald = pkgs.thermald;
in {
  imports = [
    ./tlp.nix
    ./dell.nix
  ];
  config = {
    boot.initrd.availableKernelModules = [
      # fast decrypt for luks
      "aesni_intel"

      "thunderbolt"
    ];
    boot.initrd.kernelModules = ["i915"];
    boot.blacklistedKernelModules = [
      "nouveau"
    ];

    boot.kernel.sysctl = {
      "dev.i915.perf_stream_paranoid" = 0;
    };
    boot.kernelParams = [
      # from: https://wiki.archlinux.org/title/Dell_XPS_15_(9560)#Enable_power_saving_features_for_the_i915_kernel_module

      # from 9560
      # "i915.enable_fbc=1"
      # "i915.disable_power_well=1"
      # "i915.enable_psr=2"

      # this is needed if psr is enabled from 9560
      # "i915.edp_vswing=2"
      # "i915.enable_dc=4"
      # "intel_iommu=igfx_off"

      # dec/enc support
      # "i915.enable_guc=2"

      # Make sure the laptop exposes correct acpi. Makes the laptop less crash prone
      # already included in nixos-hardware
      # "acpi_rev_override=1"

      # USB-C fix, do not sleep the pcie links
      # NOTE: as of 2024-01-12 this fix is not needed.
      # Further notes: usb auto works if there a display connected, consistently, it is only usb2 though might have to check further.
      # "pcie_aspm=off"
      "pcie_aspm=force"
      # "i915.enable_fbc=1"
      # "i915.disable_power_well=0"
      "i915.enable_psr=2"
      # "i915.fastboot=1"
      "i915.psr_safest_params=1"

      # Do not let nouveau take control of the nvidia gpu
      # already included in nixos-hardware
      #"nouveau.modeset=0"

      # Test option, to see if there is any discernible difference
      # This is not needed, it is controlled by tlp
      #"workqueue.power_efficient=1"

      # Self explanatory
      "mitigations=off"
      # coffeelake change
      "mem_sleep_default=deep"
      # "acpi_osi=!"
      # "acpi_osi=\"Windows 2009\""
      "acpi_osi=Linux"
      "acpi_rev_override"
      "psmouse.synaptics_intertouch=0"

      # "acpi_osi=\"Windows 2017.2\""
      # "nvme.noacpi=1"
    ];

    boot.initrd.luks.devices."swap".device = "/dev/disk/by-uuid/bf2ca1e2-2956-4342-b2b8-159b8750d6d0";
    networking.hostName = "nyx";

    virt.arch.intel.enable = true;
    services.hardware.bolt.enable = true;
    services.kmonad = {
      enable = true;
      keyboards = {
        laptop-internal = {
          device = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          config = ''
            (defsrc ;; Default keymap for laptop
              esc   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
              `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
              caps  a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft  z    x    c    v    b    n    m    ,    .    /    rsft up
              lctl  lmet lalt           spc            ralt rctl left down right
            )
            (deflayer qwerty ;; Default layer, just switched caps for esc, lctl for caps, and esc for lctl
              caps   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
              `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
              @cen  a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /    @rcdt up
              esc  lalt lmet           spc            ralt rctl left down right
            )
            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              ;; cen (tap-hold-next 200 (tap-next esc (tap-macro-release esc : :delay 2)) lctl)
              cen (tap-next esc lctl)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-next  \(  lsft )
              rcdt (tap-next  \)  rsft )
              ;; lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              ;; rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
        rzr-blkwd-te-bad = {
          # WARN: Was not able to debug why i need to use if01 instead of the actual event kdb, this means
          # that ripple effects wont work.
          # NOTE: even with extraGroups, for some reason this does not work reliably. This is probably explained by
          # openrazer sometimes not working in some cases.
          # TODO: (low prio) Investigate the problem, or workaround by disabling openrazer.
          device = "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-event-kbd";
          #"/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-if01-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          # This is to deal with openrazer taking over the keyboard.
          extraGroups = ["openrazer"];
          config = ''
            (defsrc ;; the sys is also a prnt scr key
              esc       f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              caps a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft z    x    c    v    b    n    m    ,    .    /    rsft                    up
              lctl lmet lalt           spc            ralt      cmp  rctl              left down rght
            )

            (deflayer qwerty ;; the sys is also a prnt scr key
              caps      f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              @cen a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /   @rcdt                    up
              esc  lmet lalt           spc            ralt      cmp  rctl              left down rght
            )
            ;; (double_tap_hold single_tap )

            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              cen (tap-hold-next 200 (tap-next esc (tap-macro esc :)) lctl)
              ;;cen (multi-tap 170 lctl esc)
              ;;cen (multi-tap 200 a 200 b 200 c d)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
        rzr-blkwd-te = {
          # NOTE: See the previous comments rzr-blkwd entry.
          device =
            #"/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-event-kbd";
            "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-if01-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          # This is to deal with openrazer taking over the keyboard.
          extraGroups = ["openrazer"];
          config = ''
            (defsrc ;; the sys is also a prnt scr key
              esc       f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              caps a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft z    x    c    v    b    n    m    ,    .    /    rsft                    up
              lctl lmet lalt           spc            ralt      cmp  rctl              left down rght
            )
            (deflayer qwerty ;; the sys is also a prnt scr key
              caps      f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              @cen a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /   @rcdt                    up
              esc  lmet lalt           spc            ralt      cmp  rctl              left down rght
            )
            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              cen (tap-hold-next 200 (tap-next esc (tap-macro esc :)) lctl)
              ;;cen (multi-tap 170 lctl esc)
              ;;cen (multi-tap 200 a 200 b 200 c d)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
      };
    };
    services.udev.packages = let
      nvidia = pkgs.writeTextFile {
        name = "nvidia rules";
        text = ''
          # Remove NVIDIA USB xHCI Host Controller devices, if present
          # ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
          # Remove NVIDIA USB Type-C UCSI devices, if present
          # ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
          # Remove NVIDIA Audio devices, if present
          # ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
          # Remove NVIDIA VGA/3D controller devices
          # ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
        '';
        destination = "/etc/udev/rules.d/99-esp32.rules";
      };
    in [
      # This is picked up by nixos-hardware btw
    ];
  };
}
