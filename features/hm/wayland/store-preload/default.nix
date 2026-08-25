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
      cp ${./gen-seed.sh} gen-seed.sh
      cp ${./test_manifest.py} test_manifest.py
      cp ${./test_unwrap.py} test_unwrap.py
      cp ${./test_record.py} test_record.py
      cp ${./test_warm.py} test_warm.py
      cp ${./test_main.py} test_main.py
      cp ${./test_gen_seed.py} test_gen_seed.py
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

  # The runtime binary name for each package -- the same value seedFor uses
  # for `bin`. Only consumed by the assertion below.
  derivedApps = lib.mapAttrsToList (_: p: baseNameOf (lib.getExe p)) cfg.packages;

  # Floors, set below measured with headroom for nixpkgs churn. The floor, not
  # the heuristic, is what makes unwrapping safe: rofi through its wrapper
  # yields 3 files against 60 unwrapped, so this fails the build instead of
  # warming two libraries. Same shape as the SECKEY_MIN_TESTS floor.
  floors = {
    rofi = 40; # measured 60
    kitty = 6; # measured 8
    quickshell = 70; # measured 99
    firefox = 3; # measured 4; a launcher shim, real set comes from record
    glide = 6; # measured 8; a firefox fork, same launcher-shim shape
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
      bash ${./gen-seed.sh} "$real" "$out"
      n=$(wc -l < "$out")
      if [ "$n" -lt ${toString floors.${name}} ]; then
        echo "seed ${name}: $n files, floor is ${toString floors.${name}}" >&2
        echo "wrapper resolution probably picked the wrong binary, or ldd failed/truncated: $real" >&2
        exit 1
      fi
    '';

  seedDir = pkgs.runCommand "store-preload-seeds" {} (
    "install -d $out\n"
    + lib.concatStringsSep "\n" (lib.mapAttrsToList
      (n: p: "cp ${seedFor n p} $out/${n}")
      cfg.packages)
  );

  # Exactly what the systemd user unit sees: writeShellApplication's
  # runtimeInputs, nothing else. Measured on the running system as
  # coreutils:findutils:gnugrep:gnused:systemd, with no tracked app. The unit
  # DOES see python3 and ldd too -- writeShellApplication also puts
  # storePreload's own runtimeInputs (python3, glibc.bin for ldd, coreutils)
  # on PATH -- so this check is stricter than the unit's real environment,
  # which is safe (a false failure here, never a false pass), not a hole.
  unitPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.systemd
  ];

  # The bug was invisible to every test because pytest inherits the developer's
  # PATH. This runs the built binary under the unit's exact PATH and asserts
  # each app individually clears its floor -- per app, not in aggregate,
  # because rofi contributed 0 while a 995 MB total looked healthy.
  # test_iocost-ab.sh applies the same technique to systemd's default PATH.
  envCheck = pkgs.runCommand "store-preload-env-check" {} ''
    out_txt=$(env -i PATH=${unitPath} HOME=/homeless-shelter \
      ${storePreload}/bin/store-preload \
      --seed-dir ${seedDir} --apps ${appArgs} \
      --state /dev/null --dry-run warm)
    echo "$out_txt"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: _: ''
        got=$(echo "$out_txt" | awk -v a=${n} '$1 == a {print $2}')
        if [ -z "$got" ] || [ "$got" -le 0 ]; then
          echo "store-preload plans 0 bytes for ${n} under the unit PATH" >&2
          exit 1
        fi
      '')
      cfg.packages)}
    touch $out
  '';

  # Nothing else depends on envCheck, and a derivation nothing depends on is
  # never built (the trap that already bit Task 5's guard). `: ${envCheck}`
  # is a no-op shell command whose only job is the string interpolation:
  # substituting envCheck's store path here makes it a real build input, so
  # a broken guard fails `home-manager build` instead of sitting dormant.
  storePreloadChecked = pkgs.runCommand "store-preload-checked" {} ''
    : ${envCheck}
    ln -s ${storePreload} $out
  '';
in {
  options.services.storePreload = {
    enable = lib.mkEnableOption "page-cache warming for hot store paths";

    apps = lib.mkOption {
      # nonEmpty: an empty list emits "--apps --workers", which argparse rejects.
      type = lib.types.nonEmptyListOf lib.types.str;
      # rofi leads because it is keybind-launched. Membership is pinned by the
      # assertion below, so adding to warmApps without adding here fails at eval.
      default = ["rofi" "kitty" "quickshell" "firefox-devedition" "glide"];
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
      default = 3 * 1024 * 1024 * 1024;
      description = ''
        Cap on bytes per warm pass. A file that would exceed it is skipped
        whole and logged, from the tail of `apps`, so the first entry survives.
        Measured union for the default apps is ~1.8 GB: two Mozilla browsers
        carry a ~177 MB libxul.so each, which dedup cannot share.
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

    # Sorted, so order stays free and only membership is constrained. Catches
    # both directions: a package with no apps entry warms nothing, and an apps
    # entry with no package silently degrades to manifest-only warming.
    assertions = [
      {
        assertion =
          lib.sort (a: b: a < b) cfg.apps == lib.sort (a: b: a < b) derivedApps;
        message = ''
          services.storePreload.apps and .packages disagree.
            apps:    ${lib.concatStringsSep " " (lib.sort (a: b: a < b) cfg.apps)}
            derived: ${lib.concatStringsSep " " (lib.sort (a: b: a < b) derivedApps)}
          Every package needs an apps entry naming its binary, and vice versa.
        '';
      }
    ];

    home.packages = [storePreloadChecked pkgs.fatrace];

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
        # storePreloadChecked, not storePreload directly: its output symlinks
        # to storePreload, but building it also forces envCheck. Going
        # through storePreload here would make the guard dormant the moment
        # anyone drops storePreloadChecked from home.packages, with zero
        # signal -- exactly the class of silent failure this whole module
        # exists to close.
        ExecStart = "${storePreloadChecked}/bin/store-preload --apps ${appArgs} --workers ${toString cfg.workers} --max-bytes ${toString cfg.maxBytes} --seed-dir ${seedDir} warm";
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
        ExecStart = "${storePreloadChecked}/bin/store-preload --apps ${appArgs} --seed-dir ${seedDir} record";
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
