{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  # nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
  cfg = config;
  sys = "/run/current-system/sw";
in {
  config = let
    lockSec = 300; # idle -> loginctl lock-session
    dpmsSec = 800; # idle -> DPMS screen off
    # idle -> systemctl suspend. Lid-close suspend already works via logind's
    # default HandleLidSwitch; this covers the lid-OPEN case, where the session
    # previously locked, blanked, and then stayed fully awake indefinitely.
    #
    # This timeout is NOT AC-aware -- nothing here, in logind, or in the
    # stay-awake popup gates it on power state, and the home-manager
    # services.swayidle module has no cheap declarative AC gate to add one
    # with. It fires identically on battery and on AC, so a long unattended
    # nixos-rebuild, a big download, or an inbound SSH session left idle for
    # 30 minutes now suspends even while plugged in, where it previously never
    # did. Arm the stay-awake toggle before leaving anything long-running
    # unattended.
    suspendSec = 1800;
    configPkg = pkgs.writeText "swaylockConfig" ''
      indicator-idle-visible
      indicator-radius=100
      indicator-thickness=7 ring-color=bb00cc
      key-hl-color=880033
      line-color=FFFFFF00
      inside-color=FFFFFF88
      show-failed-attempts
      color=000000
    '';
    swaylockScript = pkgs.writeShellScript "swaylockDebug" ''
      (echo -e "\n\nStarting swaylock:\n"; WAYLAND_DEBUG=1 ${
        lib.getExe pkgs.nw.swaylock
      } -f 2>&1 ) >> ~/swaylock_logfile
    '';
    # `ipc call lock lock` returns as soon as the lock is REQUESTED. In workspace
    # backdrop mode that is before the compositor lock actually engages (the
    # desktop capture is armed first), so returning immediately would let
    # lock.target -- and therefore sleep.target -- proceed on an unlocked
    # session. Wait, bounded, for the lock marker that Lock.qml writes when
    # `locked` becomes true.
    lockTrigger = pkgs.writeShellApplication {
      name = "qs-lock-trigger";
      runtimeInputs = [ pkgs.quickshell pkgs.coreutils ];
      text = ''
        # Fail-open by design: if qs is down / ipc fails, nothing locks.
        qs -c task-bar ipc call lock lock || exit 0
        marker="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked"
        i=0
        while [ "$i" -lt 100 ]; do
          if [ -e "$marker" ]; then
            exit 0
          fi
          sleep 0.01
          i=$((i + 1))
        done
        exit 0
      '';
    };
  in {
    xdg.configFile."swaylock/config".source = configPkg;
    # Idle-policy seam for the Quickshell "stay awake" popup: same numbers the
    # swayidle timeouts use, emitted as JSON the popup reads. Lives outside
    # ~/.config/quickshell (that dir is a repo symlink).
    xdg.configFile."quickshell-idle/policy.json".text =
      builtins.toJSON {inherit lockSec dpmsSec suspendSec;};
    # xdg
    systemd.user = {
      services = {
        # NOTE: taken from example here: https://sr.ht/~whynothugo/systemd-lock-handler/#usage
        swaylock = {
          Unit = {
            Description = "Trigger the Quickshell lock on lock.target.";
            PartOf = ["lock.target"];
            After = ["lock.target"];
          };
          Service = {
            Type = "oneshot";
            # No swaylock fallback in the active path (manual backstop only).
            # lockTrigger itself is fail-open (see its comment above).
            ExecStart = "${lockTrigger}/bin/qs-lock-trigger";
          };
          Install = {WantedBy = ["lock.target"];};
        };
      };
      targets = {
        # wayland-wm = {
        #   Unit = {
        #     Description = "Wayland target so that ";
        #     BindsTo = "graphical-session.target";
        #     After = ["sway-session.target" "hyprland-session.target"];
        #     # Wants = "swayidle.service";
        #   };
        # };
      };
    };
    services = {
      swayidle = let
        # lockScreen = "${pkgs.swaylock-effects-pr}/bin/swaylock -f";
        # TODO: (med prio) decide wether to manually override or keep using nixpkgs-wayland. Might even make this configurable
        # lockScreen = "${pkgs.nw.swaylock}/bin/swaylock -f";
        # TODO: redo service? makesure that sway starts this?
        lockScreen = "${lib.getExe pkgs.nw.swaylock} -f";
        bin = "/run/current-system/sw";
        hyprctl = "${bin}/bin/hyprctl";
        swaymsg = "${bin}/bin/swaymsg";
        # One shared swayidle drives both compositors. Pick the DPMS backend at
        # runtime from the compositor env (UWSM imports it into the systemd user
        # session, so it is present in this service's environment). state is
        # "off"/"on" for both hyprctl and swaymsg.
        mkDpms = state:
          pkgs.writeShellScript "swayidle-dpms-${state}" ''
            if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
              ${hyprctl} dispatch dpms ${state}
            else
              ${swaymsg} "output * power ${state}"
            fi
          '';
      in {
        enable = true;
        # NOTE: move towards letting logind handle most of the locking work
        # since there is a push to remove events and simply the codebase.
        # See: https://github.com/swaywm/swayidle/issues/117
        package = pkgs.nw.swayidle-test;
        # package = pkgs.swayidle.override {systemdSupport = false;};
        timeouts = [
          {
            timeout = lockSec;
            command = "${sys}/bin/loginctl lock-session";
          }
          {
            # WARN: disable, as of 7-31-2023 any wlrooots compositor that handles more than 2 monitors will not enable the third.
            # WARN: found out that this is way because of a change on how wlroots
            # handles display modifiers, and on high res displays. Setting
            # WLR_DRM_NO_MODIFIERS "fixes" this.
            timeout = dpmsSec;
            command = "${mkDpms "off"}";
            resumeCommand = "${mkDpms "on"}";
          }
          {
            timeout = suspendSec;
            command = "${sys}/bin/systemctl suspend";
          }
        ];
        # Bind to graphical-session.target (UWSM-managed) so swayidle runs and
        # stops under both sway and hyprland, started after the session env is
        # finalized (so the DPMS backend detection above sees the right vars).
        systemdTarget = "graphical-session.target";
      };
    };
  };
}
