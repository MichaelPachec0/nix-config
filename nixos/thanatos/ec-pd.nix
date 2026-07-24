{ config, lib, pkgs, ... }:
let
  cfg = config.services.ecPd;
  pollBin = pkgs.writeShellScriptBin "ec-pd-poll" ''
    set -u
    EC=/sys/kernel/debug/ec/ec0/io
    OUT=/run/ec-pd/status.json
    b() { od -An -tu1 -j "$1" -N1 "$EC" 2>/dev/null | tr -d ' '; }
    while :; do
      if [ -r "$EC" ]; then
        c2=$(b 194); f46=$(b 70); w=$(b 201); p2f=$(b 47)
        present=false; [ "''${c2:-0}" -gt 0 ] 2>/dev/null && present=true
        pd=false;      [ $(( ''${f46:-0} & 16 )) -ne 0 ] && pd=true
        cl=false;      [ $(( ''${p2f:-0} & 64 )) -ne 0 ] && cl=true
        printf '{"present":%s,"pd":%s,"watts":%s,"cableLimited":%s}\n' \
          "$present" "$pd" "''${w:-0}" "$cl" > "$OUT.tmp" && mv -f "$OUT.tmp" "$OUT"
      fi
      sleep ${toString cfg.interval}
    done
  '';
in {
  options.services.ecPd = {
    enable = lib.mkEnableOption "USB-C PD/charger state poller (EC RAM -> /run/ec-pd/status.json)";
    interval = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Seconds between EC RAM polls.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ec_sys exposes the EC RAM at /sys/kernel/debug/ec/ec0/io (READ-ONLY).
    boot.kernelModules = [ "ec_sys" ];
    boot.extraModprobeConfig = "options ec_sys write_support=0";

    systemd.services.ec-pd-poll = {
      description = "USB-C PD/charger state poller (EC RAM -> /run/ec-pd/status.json)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pollBin}/bin/ec-pd-poll";
        Restart = "always";
        RestartSec = 5;
        RuntimeDirectory = "ec-pd";
        RuntimeDirectoryMode = "0755";
        # Runs as root: debugfs (/sys/kernel/debug) is 0700 root and no capability
        # grants a non-root user access, so unlike e5800poll this cannot use a
        # dedicated user. Kept otherwise hardened; it only reads the EC + writes /run.
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = [ "" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallFilter = [ "@system-service" ];
        # NB: deliberately NOT setting ProtectKernelTunables/ProtectKernelModules --
        # they can block the debugfs read. If the read still fails at verify time,
        # that pair is the first thing to relax.
      };
    };
  };
}
