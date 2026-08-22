# Warm the page cache for the apps whose first launch after boot is the one you
# actually wait on.
#
# A cold 4 KiB fault against /nix costs ~601 us p50 here, and pulls 40.2 KiB off
# the device, because a compressed extent is 128 KiB and indivisible. Page cache
# erases that on second launch and keeps it erased: after 3d11h uptime the whole
# mapped store working set measured 100.0% resident, since swappiness=150 sends
# anon to zram before dropping mapped file pages.
#
# So the only job here is the window between boot and first launch. Not fighting
# ongoing eviction. Deliberately does not mlock.
#
# Runs after the session is up, not during boot. Boot is the contended part, and
# warming there would fight greetd, Hyprland and quickshell for the same cores.
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
      cp ${./store-preload/manifest.py} manifest.py
      cp ${./store-preload/resolve.py} resolve.py
      cp ${./store-preload/record.py} record.py
      cp ${./store-preload/warm.py} warm.py
      cp ${./store-preload/main.py} main.py
      cp ${./store-preload/test_manifest.py} test_manifest.py
      cp ${./store-preload/test_resolve.py} test_resolve.py
      cp ${./store-preload/test_record.py} test_record.py
      cp ${./store-preload/test_warm.py} test_warm.py
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
      type = lib.types.listOf lib.types.str;
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
    environment.systemPackages = [storePreload];

    # User units: graphical-session.target is user-scoped. Puts the manifest
    # under XDG_STATE_HOME in /home, which survives the root rollback.
    systemd.user.services.store-preload = {
      description = "Warm the page cache for hot store paths";
      wantedBy = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${storePreload}/bin/store-preload --apps ${appArgs} --workers ${toString cfg.workers} --max-bytes ${toString cfg.maxBytes} warm";
        # Best-effort, not idle: idle can starve indefinitely, and the point
        # is to finish before the user hits the rofi keybind.
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 6;
        Nice = 5;
      };
    };

    systemd.user.services.store-preload-record = {
      description = "Record store files the tracked apps map";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${storePreload}/bin/store-preload --apps ${appArgs} record";
        Nice = 10;
      };
    };

    # Frequent: scan costs under 10 ms and rofi only lives ~2s at a time.
    systemd.user.timers.store-preload-record = {
      description = "Periodically record store files the tracked apps map";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnActiveSec = "2min";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
        Unit = "store-preload-record.service";
      };
    };
  };
}
