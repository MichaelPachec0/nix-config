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
  in {
    xdg.configFile."swaylock/config".source = configPkg;
    # xdg
    systemd.user = {
      services = {
        # NOTE: taken from example here: https://sr.ht/~whynothugo/systemd-lock-handler/#usage
        swaylock = {
          Unit = {
            Description = "service runs on dbus lock event. (systemd-lock-handler is required)";
            OnSuccess = ["unlock.target"];
            PartOf = ["lock.target"];
            After = ["lock.target"];
          };
          Service = {
            Type = "forking";
            # TODO: (med prio) change this so that it can configurable by the user.
            ExecStart = "${lib.getExe pkgs.nw.swaylock} -f -i %h/.local/share/lockscreen.png";
            Restart = "on-failure";
          };
          Install = {WantedBy = ["lock.target"];};
        };
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
      in {
        enable = true;
        # NOTE: move towards letting logind handle most of the locking work
        # since there is a push to remove events and simply the codebase.
        # See: https://github.com/swaywm/swayidle/issues/117
        package = pkgs.nw.swayidle.override {systemdSupport = false;};
        timeouts = [
          {
            timeout = 300;
            command = "${sys}/bin/loginctl lock-session";
          }
          {
            # WARN: disable, as of 7-31-2023 any wlrooots compositor that handles more than 2 monitors will not enable the third.
            # WARN: found out that this is way because of a change on how wlroots
            # handles display modifiers, and on high res displays. Setting
            # WLR_DRM_NO_MODIFIERS "fixes" this.
            timeout = 800;
            # TODO: (med prio) write a bash script that checks which enviroment we
            # are in.
            # command = "${hyprctl} dispatch dpms off";
            # resumeCommand = "${hyprctl} dispatch dpms on";
            command = "${swaymsg} \"output * power off\"";
            resumeCommand = "${swaymsg} \"output * power on\"";
          }
        ];
        systemdTarget = "wayland-wm.target";
      };
    };
  };
}

