# Health gate for boot counting: what makes a boot "good".
#
# boot-health.service is RequiredBy boot-complete.target. When it fails the
# target is never reached, systemd-bless-boot never blesses the entry, and
# systemd-boot falls back to the previous generation once the tries are
# spent. boot-health-timeout burns a try when the generation is up but
# never became healthy, and the hardware watchdog burns one when the kernel
# hangs. The checks are deliberately minimal: route, sshd, zerotier. A
# service failing after that is not this module's business.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.bootHealth;
  bootHealth = pkgs.writeShellApplication {
    name = "boot-health";
    runtimeInputs = with pkgs; [iproute2 gnugrep coreutils] ++ lib.optional (cfg.zerotierNetwork != null) config.services.zerotierone.package;
    text = builtins.readFile ./scripts/boot-health.sh;
  };
  bootHealthTimeout = pkgs.writeShellApplication {
    name = "boot-health-timeout";
    runtimeInputs = with pkgs; [config.systemd.package coreutils];
    text = builtins.readFile ./scripts/boot-health-timeout.sh;
  };
in {
  options.local.bootHealth = {
    enable = lib.mkEnableOption "boot health gate on boot-complete.target";
    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "Port sshd must be listening on for the boot to count as good.";
    };
    zerotierNetwork = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "zerotier network id that must report OK; null skips the check.";
    };
    timeoutMinutes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Minutes after boot before an unblessed, unhealthy generation is rebooted.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.boot-health = {
      description = "Boot health gate (route, sshd, zerotier)";
      requiredBy = ["boot-complete.target"];
      before = ["boot-complete.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "sshd.service"] ++ lib.optional (cfg.zerotierNetwork != null) "zerotierone.service";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe bootHealth;
        # The script's own budgets sum to 480s; give systemd a little more.
        TimeoutStartSec = "600s";
        # A finished oneshot without this reports inactive, and the Task 7
        # VM test waits on boot-health.service being active.
        RemainAfterExit = true;
      };
      environment = {
        BOOT_HEALTH_SSH_PORT = toString cfg.sshPort;
        BOOT_HEALTH_ZT_NETWORK = lib.optionalString (cfg.zerotierNetwork != null) cfg.zerotierNetwork;
      };
    };

    systemd.timers.boot-health-timeout = {
      description = "Reboot an unblessed generation that never became healthy";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "${toString cfg.timeoutMinutes}min";
        AccuracySec = "30s";
      };
    };
    systemd.services.boot-health-timeout = {
      description = "Reboot if the booted entry is still counted and unhealthy";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe bootHealthTimeout;
      };
      environment.BLESS_BOOT = "${config.systemd.package}/lib/systemd/systemd-bless-boot";
    };

    # A frozen kernel must also burn a try instead of sitting there. The
    # watchdog kernel module is per host (sp5100_tco on kore, softdog on
    # selene) and lives in the host configuration.
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "30s";
      RebootWatchdogSec = "2min";
    };
  };
}
