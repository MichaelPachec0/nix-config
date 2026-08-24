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
  warmApps,
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
      cp ${./unwrap.py} unwrap.py
      cp ${./record.py} record.py
      cp ${./warm.py} warm.py
      cp ${./main.py} main.py
      cp ${./test_manifest.py} test_manifest.py
      cp ${./test_unwrap.py} test_unwrap.py
      cp ${./test_record.py} test_record.py
      cp ${./test_warm.py} test_warm.py
      cp ${./test_main.py} test_main.py
      mypy --strict ./*.py
      python3 -m unittest discover -p 'test_*.py' -v
      install -d "$out"
      cp manifest.py unwrap.py record.py warm.py main.py "$out/"
    '';

  # seed resolver needs ldd, which lives in glibc.bin
  storePreload = pkgs.writeShellApplication {
    name = "store-preload";
    runtimeInputs = [pkgs.python3 pkgs.glibc.bin pkgs.coreutils];
    text = ''exec python3 ${storePreloadSrc}/main.py "$@"'';
  };

  appArgs = lib.concatStringsSep "," cfg.apps;

  # Floors, set below measured with headroom for nixpkgs churn. The floor, not
  # the heuristic, is what makes unwrapping safe: rofi through its wrapper
  # yields 3 files against 60 unwrapped, so this fails the build instead of
  # warming two libraries. Same shape as the SECKEY_MIN_TESTS floor.
  floors = {
    rofi = 40; # measured 60
    kitty = 6; # measured 8
    quickshell = 70; # measured 99
    firefox = 3; # measured 4; a launcher shim, real set comes from record
  };

  # bin comes from the package, not the manifest key: warmApps.firefox is
  # config.programs.firefox.package, whose binary is firefox-devedition.
  seedFor = name: pkg: let
    bin = lib.getExe pkg;
  in
    pkgs.runCommand "store-preload-seed-${name}" {
      nativeBuildInputs = [pkgs.python3 pkgs.glibc.bin];
    } ''
      real=$(python3 -c "import sys; sys.path.insert(0, '${storePreloadSrc}'); import unwrap; print(unwrap.resolve(sys.argv[1]))" "${bin}")
      { echo "$real"; ldd "$real" | grep -o '/nix/store/[^ )]*'; } | sort -u > "$out"
      n=$(wc -l < "$out")
      if [ "$n" -lt ${toString floors.${name}} ]; then
        echo "seed ${name}: $n files, floor is ${toString floors.${name}}" >&2
        echo "wrapper resolution probably picked the wrong binary: $real" >&2
        exit 1
      fi
    '';

  seedDir = pkgs.runCommand "store-preload-seeds" {} (
    "install -d $out\n"
    + lib.concatStringsSep "\n" (lib.mapAttrsToList
      (n: p: "cp ${seedFor n p} $out/${n}")
      cfg.packages)
  );
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

    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      description = ''
        Apps to warm, as packages. Set from warmApps so the warm set and the
        bind set are the same object. Names are the manifest keys.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.storePreload.packages = lib.mkDefault warmApps;

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
        ExecStart = "${storePreload}/bin/store-preload --apps ${appArgs} --workers ${toString cfg.workers} --max-bytes ${toString cfg.maxBytes} --seed-dir ${seedDir} warm";
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
        ExecStart = "${storePreload}/bin/store-preload --apps ${appArgs} --seed-dir ${seedDir} record";
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
