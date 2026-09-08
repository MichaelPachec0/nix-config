# Nightly upgrade from the flake, staged as a boot entry, activated by a
# windowed reboot. Never `switch`: the running system is replaced only
# through a counted boot that boot-health judges (see boot-health.nix and
# the boot-counting directory).
#
# nixos-upgrade.service is upstream's (system.autoUpgrade); this module adds
# the halt-file condition (boot-fallback-alert writes it after a fallback so
# the same broken generation is not rebuilt and rebooted into every night),
# an OnFailure alert, and an OnSuccess reboot step.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.autoUpgrade;
  ntfy = config.local.ntfy;
  rebootScript = pkgs.writeShellApplication {
    name = "auto-upgrade-reboot";
    runtimeInputs = with pkgs; [coreutils config.systemd.package];
    text = builtins.readFile ./scripts/auto-upgrade-reboot.sh;
  };
in {
  options.local.autoUpgrade = {
    enable = lib.mkEnableOption "nightly staged upgrade with windowed reboot";
    flake = lib.mkOption {
      type = lib.types.str;
      default = "github:MichaelPachec0/nix-config";
      description = "Flake reference nixos-rebuild boots from.";
    };
    rebootWindow = {
      lower = lib.mkOption {
        type = lib.types.strMatching "[0-9]{2}:[0-9]{2}";
        default = "03:00";
      };
      upper = lib.mkOption {
        type = lib.types.strMatching "[0-9]{2}:[0-9]{2}";
        default = "05:00";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = ntfy.enable;
        message = "local.autoUpgrade needs local.ntfy.enable for the failure alert.";
      }
    ];

    system.autoUpgrade = {
      enable = true;
      inherit (cfg) flake;
      operation = "boot";
      flags = ["--refresh" "-L"];
      dates = "02:30";
      randomizedDelaySec = "10min";
      # Upstream's reboot logic only fires on kernel changes; ours below
      # compares whole generations.
      allowReboot = false;
    };

    systemd.services.nixos-upgrade = {
      unitConfig = {
        # Written by boot-fallback-alert after a fallback; removed by hand
        # once the configuration is fixed.
        ConditionPathExists = "!/var/lib/auto-upgrade/halted";
        OnFailure = ["upgrade-failed-alert.service"];
        OnSuccess = ["auto-upgrade-reboot.service"];
      };
    };

    systemd.services.auto-upgrade-reboot = {
      description = "Reboot into the staged generation inside the window";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe rebootScript;
      };
      environment = {
        WINDOW_LOWER = cfg.rebootWindow.lower;
        WINDOW_UPPER = cfg.rebootWindow.upper;
      };
    };

    systemd.services.upgrade-failed-alert = {
      description = "Alert: nightly upgrade failed";
      path = [ntfy.package config.systemd.package pkgs.hostname];
      serviceConfig = {
        Type = "oneshot";
        LoadCredential = ntfy.loadCredential;
      };
      script = ''
        journalctl -u nixos-upgrade.service -n 30 --no-pager \
          | ntfy-send "$(hostname): nightly upgrade failed" high warning
      '';
    };

    systemd.tmpfiles.rules = ["d /var/lib/auto-upgrade 0755 root root -"];
  };
}
