# Watchdog that clears keyboard keys the kernel wrongly believes are held. PS/2
# keyboards have limited n-key rollover, so when many keys go down at once the
# i8042 matrix ghosts, the controller drops RELEASE scancodes and the kernel's
# key bitmap reports those keys down forever.
#
# The symptom is misleading: libinput's disable-while-typing gates touchpads but
# not pointing sticks, so a permanently-"typing" keyboard reads as dead touchpad
# hardware with a working trackpoint. A stuck modifier is worse -- every
# keystroke becomes a chord.
#
# The fix is to inject the missing release into /dev/input/eventN, which fans
# out to every handler including libinput; nothing is restarted, and releasing
# an already-up key is a no-op, so it is idempotent.
#
# Deliberately NOT a keybind: a stuck trigger key never re-fires (libinput
# filters kernel autorepeat) and a stuck modifier makes every bind misfire.
# Daemon logic: ./fix_stuck_keys.py, helpers covered by ./fix_stuck_keys_test.py.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.fixStuckKeys;

  # libnotify so an automatic release announces itself: silently mutating input
  # state would be worse than the bug.
  daemon = pkgs.writeShellApplication {
    name = "fix-stuck-keys";
    runtimeInputs = [pkgs.python3 pkgs.libnotify];
    text = ''
      exec python3 ${./fix_stuck_keys.py} "$@"
    '';
  };
in {
  options.services.fixStuckKeys = {
    enable = lib.mkEnableOption "the stuck-key watchdog (releases keys the kernel thinks are held)";

    catKeys = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        How many non-modifier keys must be held simultaneously to count as the
        "cat on the keyboard" signature. Ordinary typing and chords never park
        this many non-modifier keys down for catHoldSeconds.
      '';
    };

    catHoldSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = ''
        How long the catKeys set must stay continuously down before it is
        treated as ghosted. Well past any real chord, well under the point
        where a muted touchpad becomes annoying.
      '';
    };

    loneHoldSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        How long a single key may stay down before it is released. Much longer
        than catHoldSeconds, because one held key is the shape of a legitimate
        long press.
      '';
    };

    gpuBusyPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 45;
      description = ''
        Above this GPU utilisation the machine is assumed to be actively driven
        (a game holding movement keys, video playback) and held keys are left
        alone -- a legitimately held key is indistinguishable from a stuck one
        by key bitmap alone. Read from
        /sys/class/drm/card*/device/gpu_busy_percent, the same node the
        task-bar's gpu-stats.sh uses; the amdgpu iGPU idles around 0-5%.
        The manual `fix-stuck-keys` CLI ignores this gate entirely.
      '';
    };

    pollSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "How often to read the kernel key bitmaps.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Also the manual CLI: `fix-stuck-keys` releases everything held right now
    # (no heuristics, no GPU gate), `--check` only reports. This is the escape
    # hatch a stuck keyboard cannot block, since it runs over SSH too.
    home.packages = [daemon];

    # /dev/input/event* is crw-rw---- root:input, so this needs the `input`
    # group; the user service inherits the login session's groups.
    systemd.user.services.fix-stuck-keys = {
      Unit = {
        Description = "Release keyboard keys the kernel wrongly believes are held";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Install.WantedBy = ["graphical-session.target"];
      Service = {
        ExecStart = lib.concatStringsSep " " [
          "${daemon}/bin/fix-stuck-keys"
          "--daemon"
          "--cat-keys=${toString cfg.catKeys}"
          "--cat-hold-seconds=${toString cfg.catHoldSeconds}"
          "--lone-hold-seconds=${toString cfg.loneHoldSeconds}"
          "--gpu-busy-percent=${toString cfg.gpuBusyPercent}"
          "--poll-seconds=${toString cfg.pollSeconds}"
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
