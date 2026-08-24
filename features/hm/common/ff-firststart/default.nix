# Forensics for the first firefox launch after the compositor starts: it takes
# ~5s and sometimes reports a bad profile, while later launches are fine.
#
# Two things make that launch unobservable by default. Firefox's stderr goes to
# the compositor and Hyprland does not log child stderr, so whatever firefox
# prints about the profile is simply lost. And nothing records what else was
# running at that moment -- store-preload warms ~1GB on the same target, so the
# contended state has to be sampled, not reconstructed afterwards.
#
# Off by default. Enable, switch, reboot, launch firefox once, then:
#   ff-firststart report
#
#   services.ffFirstStart.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ffFirstStart;

  # The package home-manager actually puts on PATH. Load-bearing: firefox pins
  # its install location in compatibility.ini (LastPlatformDir), so execing a
  # different path would trigger an upgrade pass -- startupCache rebuild and
  # compatibility.ini rewrite -- and manufacture the slow first start this
  # harness exists to measure. Verify after switching that LastPlatformDir is
  # unchanged; if it moved, the shim is contaminating the experiment.
  firefoxPkg = config.programs.firefox.finalPackage or config.programs.firefox.package;
  firefoxBin = lib.getExe' firefoxPkg "firefox-devedition";

  # Plain text plus an explicit interpreter rather than writers.writePython3,
  # which gates the build on flake8 and would turn a lint nit in a diagnostic
  # script into a failed home-manager switch.
  harness = pkgs.writeShellApplication {
    name = "ff-firststart";
    runtimeInputs = [pkgs.coreutils pkgs.systemd];
    text = ''
      export FF_FS_DIR=${lib.escapeShellArg cfg.stateDir}
      export FF_FS_SECONDS=${toString cfg.seconds}
      exec ${pkgs.python3}/bin/python3 ${./ff_firststart.py} "$@"
    '';
  };

  # Binary name inside the derivation is load-bearing, not cosmetic: uwsm
  # derives bin_id from the launched binary's name, so a shim named anything
  # other than firefox-devedition makes app-run silently degrade to a plain
  # exec (no plugin loads). Keeping the name identical is what lets the
  # keybind path point straight at the shim's store path below.
  shim = pkgs.writeShellApplication {
    name = "firefox-devedition";
    runtimeInputs = [pkgs.coreutils pkgs.gawk pkgs.findutils pkgs.gnused pkgs.systemd];
    text = ''
      FIREFOX_BIN=${lib.escapeShellArg firefoxBin}
      FF_FS_DIR=${lib.escapeShellArg cfg.stateDir}
    ''
    + builtins.readFile ./ff-wrap.sh;
  };

  # Regression guard on ff-wrap.sh's "nothing here may stop firefox from
  # starting" invariant -- the only guard on the "user loses their browser"
  # bug that took three fix rounds to nail down. store-preload's python
  # suite is enforced at build via mypy+unittest inside its own derivation;
  # this is the shell equivalent. writeShellApplication's own checkPhase
  # argument would REPLACE shellDryRun+shellcheck rather than add to them, so
  # this runs as a separate runCommand instead, wired the same way
  # store-preload's envCheck forces itself into storePreloadChecked.
  shimCheck = pkgs.runCommand "ff-firststart-shim-check" {} ''
    bash ${./test_ff-wrap.sh} ${./ff-wrap.sh}
    touch $out
  '';

  # A derivation nothing depends on is never built. `: ${shimCheck}` forces
  # it into shimChecked's build graph via string interpolation, so editing
  # ff-wrap.sh and breaking the regression test fails the switch instead of
  # sitting dormant with zero signal.
  shimChecked = pkgs.runCommand "ff-firststart-shim-checked" {} ''
    : ${shimCheck}
    ln -s ${shim} $out
  '';
in {
  options.services.ffFirstStart = {
    enable =
      lib.mkEnableOption
      "firefox first-launch forensics (debug harness; shadows firefox-devedition on PATH)";

    seconds = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = "Watcher deadline. It also stops 20s after firefox exits.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/ff-firststart";
      description = "Where run artifacts land. Must survive reboot.";
    };

    launchPaths = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      # Computed from cfg.enable directly (rather than set under config's
      # mkIf) so this stays the option's only definition -- readOnly rejects
      # a second one, even from the same module.
      default = lib.optionalAttrs cfg.enable {
        firefox = "${shimChecked}/bin/firefox-devedition";
      };
      readOnly = true;
      description = ''
        App name -> absolute store path of the harness shim to launch instead
        of the plain binary. Consumed by keybind definitions so that app-run
        (systemd-run --user) resolves the shim directly instead of relying on
        PATH order, which the systemd user manager does not share with
        ~/.local/bin. Empty when the harness is disabled.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Forces shimCheck to build on every switch, harness enabled or not:
      # it is the only guard on ff-wrap.sh's "user loses their browser"
      # invariant, and a switch made while disabled must still catch a
      # broken edit. home.activation touches no package/profile, so this
      # installs nothing visible -- same `: ${drv}` forcing idiom as
      # store-preload's envCheck, just via activation text instead of a
      # runCommand symlink.
      home.activation.ffFirstStartShimCheck = lib.hm.dag.entryAnywhere ''
        : ${shimChecked}
      '';
    }
    (lib.mkIf cfg.enable {
      home.packages = [harness];

      # Not home.packages: a package named firefox-devedition would collide with
      # firefox itself in the same profile. ~/.local/bin precedes ~/.nix-profile/bin
      # on PATH, so this shadows it, and home-manager removes the link when the
      # option goes back to false. Terminal launches (which do use PATH) are
      # still captured this way; launchPaths above is what fixes the keybind
      # path, which goes through app-run against the systemd user manager's PATH.
      #
      # The desktop entry's `Exec=firefox-devedition %U` is left untouched, so
      # uwsm still derives the same bin_id and app2unit does not silently
      # degrade to a plain exec.
      home.file.".local/bin/firefox-devedition" = {
        source = "${shimChecked}/bin/firefox-devedition";
        executable = true;
      };

      systemd.user.services.ff-firststart = {
        Unit = {
          Description = "Firefox first-launch forensics (debug harness)";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Install.WantedBy = ["graphical-session.target"];
        Service = {
          Type = "simple";
          # Snapshot before firefox can start, and again once it has exited.
          ExecStartPre = "${harness}/bin/ff-firststart snapshot pre";
          ExecStart = "${harness}/bin/ff-firststart watch";
          ExecStopPost = "${harness}/bin/ff-firststart snapshot post";
          Nice = 10;
          SyslogIdentifier = "ff-firststart";
        };
      };
    })
  ];
}
