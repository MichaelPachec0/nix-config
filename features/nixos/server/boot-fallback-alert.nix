# Detects a systemd-boot fallback to an older generation on the next
# successful boot, halts nightly upgrades, and alerts once through ntfy.
# See scripts/boot-fallback-alert.sh for the detection rule.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.bootFallbackAlert;
  ntfy = config.local.ntfy;
  script = pkgs.writeShellApplication {
    name = "boot-fallback-alert";
    runtimeInputs = with pkgs; [coreutils gnused hostname config.systemd.package];
    text = builtins.readFile ./scripts/boot-fallback-alert.sh;
  };
in {
  options.local.bootFallbackAlert = {
    enable = lib.mkEnableOption "alert and halt upgrades after a boot fallback";
    ntfySend = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Program that receives TITLE PRIORITY TAGS and the body on stdin.
        Null means use local.ntfy's sender
        (`''${config.local.ntfy.package}/bin/ntfy-send`); set this to a
        path to override it (tests stub it this way).
      '';
    };
  };

  config = lib.mkIf cfg.enable (let
    sender =
      if cfg.ntfySend != null
      then cfg.ntfySend
      else "${ntfy.package}/bin/ntfy-send";
  in {
    assertions = [
      {
        assertion = ntfy.enable || cfg.ntfySend != null;
        message = "local.bootFallbackAlert needs either local.ntfy.enable or an explicit local.bootFallbackAlert.ntfySend.";
      }
    ];

    systemd.services.boot-fallback-alert = {
      description = "Report a boot fallback and halt nightly upgrades";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "boot-health.service"];
      serviceConfig = {
        Type = "oneshot";
        # A finished oneshot otherwise reports inactive; the Task 7 VM
        # test waits on this unit being active.
        RemainAfterExit = true;
        ExecStart = lib.getExe script;
        StateDirectory = "auto-upgrade";
        LoadCredential = lib.mkIf ntfy.enable ntfy.loadCredential;
      };
      environment.NTFY_SEND = toString sender;
    };
  });
}
