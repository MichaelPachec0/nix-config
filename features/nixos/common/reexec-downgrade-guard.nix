{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.reexecDowngradeGuard;

  # One check per guarded process. switch-to-configuration runs it before
  # it changes anything. $1 = new toplevel, $2 = action. NixOS runs each
  # check in a subshell, so `exit` stops only this check.
  mkCheck = name: p: ''
    case "$2" in
      switch | test | check) ;;
      *) exit 0 ;;   # boot / dry-activate never reexec anything
    esac

    coreutils=${pkgs.coreutils}/bin

    # "/nix/store/<hash>-systemd-261.2/lib/systemd/systemd" -> "261.2".
    # Fails (empty) when the path is not a versioned store path.
    store_version() {
      local dir="$1"
      dir="''${dir#/nix/store/}"
      dir="''${dir%%/*}"           # <hash>-systemd-261.2
      dir="''${dir#*-}"            # systemd-261.2
      [[ "$dir" =~ ^${lib.escapeRegex name}-([0-9][^/]*)$ ]] || return 1
      printf '%s\n' "''${BASH_REMATCH[1]}"
    }

    target=$($coreutils/readlink -f "$1/${p.target}") || {
      echo "${name}: cannot resolve $1/${p.target}" >&2
      exit 1
    }
    target_ver=$(store_version "$target") || {
      echo "${name}: target $target is not a versioned ${name} store path" >&2
      exit 1
    }

    # Find each live process that runs one of the guarded exes. The check
    # runs as root, so /proc/<pid>/exe is readable. GUARD_PROC lets tests
    # point the check at a fake /proc tree without root.
    proc="''${GUARD_PROC:-/proc}"
    suffixes=(${lib.concatMapStringsSep " " lib.escapeShellArg p.exes})
    bad=0
    found=0
    for exe in "$proc"/[0-9]*/exe; do
      link=$($coreutils/readlink "$exe" 2>/dev/null) || continue
      link="''${link% (deleted)}"
      match=0
      for suffix in "''${suffixes[@]}"; do
        [[ "$link" == *"/$suffix" ]] && match=1
      done
      [ "$match" = 1 ] || continue
      found=1

      pid="''${exe#"$proc"/}"; pid="''${pid%/exe}"
      running_ver=$(store_version "$link") || {
        echo "${name}: pid $pid runs $link, which is not a versioned ${name} store path" >&2
        exit 1
      }
      [ "$running_ver" = "$target_ver" ] && continue

      newest=$(printf '%s\n%s\n' "$running_ver" "$target_ver" | $coreutils/sort -V | $coreutils/tail -n1)
      if [ "$newest" != "$target_ver" ]; then
        echo "${name}: pid $pid runs ${name} $running_ver, the new configuration ships $target_ver" >&2
        bad=1
      fi
    done

    # Not an error: the process may not run, or the caller is not root.
    [ "$found" = 1 ] || echo "${name}: no live instance found, nothing to compare" >&2

    if [ "$bad" = 1 ]; then
      cat >&2 <<EOF
    ${name}: refusing to reexec a running process into an OLDER binary.
    Use 'nixos-rebuild boot' and reboot, or NIXOS_NO_CHECK=1 if the downgrade is deliberate.
    EOF
      exit 1
    fi
  '';
in {
  options.local.reexecDowngradeGuard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Refuse `nixos-rebuild switch` and `test` when a guarded process
        would reexec into an OLDER binary. A process that reexecs with
        serialized state (systemd PID 1, the user managers) can read that
        state incorrectly after a downgrade and stop. `boot` does not
        reexec, so it is always permitted.
      '';
    };

    processes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          target = lib.mkOption {
            type = lib.types.str;
            description = ''
              Path, relative to the new toplevel, whose resolved store path
              carries the version the new configuration would run.
            '';
          };
          exes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = ''
              Path suffixes (matched against /proc/<pid>/exe, anchored at a
              "/" boundary) that identify live instances of this process.
            '';
          };
        };
      });
      default = {};
      description = ''
        Guarded processes, keyed by the store name prefix of their package
        (the "systemd" in "systemd-261.2"). The key is used to parse the
        version out of the store path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    local.reexecDowngradeGuard.processes.systemd = {
      # switch-to-configuration reexecs PID 1 when this path changes. It
      # reexecs the user managers on each switch. All use this binary.
      #
      # 2026-09-07: a switch moved PID 1 from 261.2 to 261.1 caused a loop and
      # wedged the system.
      target = "systemd";
      exes = ["lib/systemd/systemd"];
    };

    system.preSwitchChecks = lib.mapAttrs' (name: p:
      lib.nameValuePair "reexecDowngradeGuard-${name}" (mkCheck name p))
    cfg.processes;
  };
}
