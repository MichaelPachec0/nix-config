# Warm the page cache for the apps whose first launch after boot you wait on.
# A cold 4 KiB fault against /nix costs ~601 us p50 here.
#
# Runs after the session is up, not during boot: warming at boot would fight
# greetd, Hyprland and quickshell for the same cores. Does not mlock.
#
# Home-manager module, not NixOS: creates only user units and a manifest under
# XDG_STATE_HOME, and Task 3's warmApps needs config.programs.rofi.finalPackage,
# which exists only in HM config. Home-manager here is standalone, so a NixOS
# module cannot read it.
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.services.storePreload;

  # mypy --strict + unittest at build time, per the ryzen-smu-bridge idiom.
  # A type error or failing test fails the build, not the machine.
  storePreloadSrc =
    pkgs.runCommand "store-preload-src" {
      nativeBuildInputs = [pkgs.python3 pkgs.mypy];
    } ''
      cp ${./manifest.py} manifest.py
      cp ${./resolve.py} resolve.py
      cp ${./record.py} record.py
      cp ${./warm.py} warm.py
      cp ${./main.py} main.py
      cp ${./test_manifest.py} test_manifest.py
      cp ${./test_resolve.py} test_resolve.py
      cp ${./test_record.py} test_record.py
      cp ${./test_warm.py} test_warm.py
      cp ${./test_main.py} test_main.py
      mypy --strict ./*.py
      python3 -m unittest discover -p 'test_*.py' -v
      install -d "$out"
      cp manifest.py resolve.py record.py warm.py main.py "$out/"
    '';

  # seed resolver needs ldd, which lives in glibc.bin
  storePreload = pkgs.writeShellApplication {
    name = "store-preload";
    runtimeInputs = [pkgs.python3 pkgs.glibc.bin pkgs.coreutils];
    text = ''exec python3 ${storePreloadSrc}/main.py "$@"'';
  };

  appArgs = lib.concatStringsSep "," cfg.apps;
in {
  options.services.storePreload = {
    enable = lib.mkEnableOption "page-cache warming for hot store paths";

    apps = lib.mkOption {
      # nonEmpty: an empty list emits "--apps --workers", which argparse rejects.
      type = lib.types.nonEmptyListOf lib.types.str;
      default = ["rofi" "kitty" "quickshell" "firefox-devedition"];
      description = ''
        Apps to seed, record and warm, in warm order. First entry warms first.
        rofi leads because it is bound to a key.
      '';
    };

    workers = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = ''
        Parallel readers. 4 is measured, not chosen: cold compressed reads go
        722 -> 1469 MB/s from 1 reader to 4, then degrade as decompression
        competes with the readers for cores.
      '';
    };

    maxBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2 * 1024 * 1024 * 1024;
      description = ''
        Cap on bytes per warm pass. A file that would exceed it is skipped
        whole and logged. Measured working set for the default apps is ~1.4 GB.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [storePreload pkgs.fatrace];

    # User units: graphical-session.target is user-scoped. Puts the manifest
    # under XDG_STATE_HOME in /home, which survives the root rollback.
    systemd.user.services.store-preload = {
      Unit = {
        Description = "Warm the page cache for hot store paths";
        After = ["graphical-session.target"];
      };
      Install.WantedBy = ["graphical-session.target"];
      Service = {
        Type = "oneshot";
        ExecStart = "${storePreload}/bin/store-preload --apps ${appArgs} --workers ${toString cfg.workers} --max-bytes ${toString cfg.maxBytes} warm";
        # Best-effort, not idle: idle can starve indefinitely, and the point
        # is to finish before the user hits the rofi keybind.
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 6;
        Nice = 5;
      };
    };

    # Session-gated: nothing to record, and no reason to wake, outside one.
    systemd.user.services.store-preload-record = {
      Unit = {
        Description = "Record store files the tracked apps map";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${storePreload}/bin/store-preload --apps ${appArgs} record";
        Nice = 10;
      };
    };

    # Frequent: scan costs under 10 ms and rofi only lives ~2s at a time.
    systemd.user.timers.store-preload-record = {
      Unit = {
        Description = "Periodically record store files the tracked apps map";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Install.WantedBy = ["graphical-session.target"];
      Timer = {
        OnActiveSec = "2min";
        # 30s was pointless churn: a full /proc scan twice a minute, forever.
        OnUnitActiveSec = "5min";
        AccuracySec = "5s";
        Unit = "store-preload-record.service";
      };
    };
  };
}
