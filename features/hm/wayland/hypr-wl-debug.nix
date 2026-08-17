# Home-manager side of the Wayland-debug Hyprland session.
#
# The bar vanishing on resume is not a crash: Hyprland posts a Wayland protocol
# error and destroys the client, and Qt's Wayland plugin answers a dead display
# with _exit(1). No SIGSEGV, so no coredump, no quickshell crash report, and
# every buffered log write is discarded -- including Qt's own "Wayland protocol
# error on interface X", the one line that would name the culprit. The only
# place the offending request/error pair survives is WAYLAND_DEBUG output, and
# only if another process is already holding it when quickshell goes. Hence
# qs-wl-ring (./qs_wl_ring.py): a reader that keeps the tail in memory and
# flushes on EOF, which is what _exit(1) produces on the pipe.
#
# Gated rather than always on, because the trace is tens of thousands of lines
# a minute and the failure needs a real suspend/resume to reproduce, so it must
# be selectable at login. ../../nixos/desktop/wayland/hyprland-wldebug.nix adds
# the greeter entry that sets HYPR_WL_DEBUG=1 for the whole session.
{
  config,
  lib,
  pkgs,
  appRun,
  ...
}: let
  wlRing = pkgs.writeShellApplication {
    name = "qs-wl-ring";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec python3 ${./qs_wl_ring.py} "$@"
    '';
  };

  defaultLog = "${config.xdg.stateHome}/quickshell/wl-tail.log";

  # Its own script rather than an `sh -c` string, so the pipeline lives INSIDE
  # the app2unit scope: `systemd-run --scope` execs in place, so a pipeline
  # assembled outside would leave the ring reader outside the scope and release
  # it the moment quickshell exited, taking down the reader holding the evidence.
  #
  # `qs -c task-bar` stays verbatim: the lock watchdog and lock-escape find the
  # bar with `pgrep -f 'quickshell -c task-bar'`, so a traced launch with a
  # different command line would make the watchdog declare every legitimate lock
  # stranded and unlock it.
  #
  # `qs` is deliberately unqualified, so the traced branch provably runs the
  # same binary as the untraced one below.
  #
  # This used to also be a correctness requirement: ./quickshell.nix installed
  # an overrideAttrs of pkgs.quickshell rather than pkgs.quickshell itself, so
  # naming the latter shadowed the profile binary and the traced session died
  # on the lock backdrop's Qt5Compat.GraphicalEffects import. That is no longer
  # true -- the qt5compat buildInput, the runtime-deps PATH prefix and both
  # patches now live in the `quickshellPatched` overlay (helpers/overlays.nix,
  # listed in baseDesktop), so pkgs.quickshell IS the patched package for both
  # NixOS and home-manager. Verified 2026-08-16: nixosConfigurations.thanatos
  # and homeConfigurations."michael-thanatos" evaluate pkgs.quickshell to the
  # same drv. Leaving `qs` unqualified is now a simplicity choice, not a trap
  # being avoided.
  tracedBar = pkgs.writeShellApplication {
    name = "qs-bar-traced";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      log="''${QS_WL_LOG:-${defaultLog}}"
      lines="''${QS_WL_LINES:-200000}"
      mkdir -p "$(dirname "$log")"

      WAYLAND_DEBUG=client qs -c task-bar 2>&1 | ${wlRing}/bin/qs-wl-ring "$log" "$lines"
    '';
  };

  # The bar's autostart, with exactly one conditional in it. Both branches keep
  # `-s b -a quickshell`, so the shell lands in background-graphical.slice with
  # its memory.low protection either way (nixos/thanatos/memory.nix).
  barLaunch = pkgs.writeShellApplication {
    name = "qs-bar-launch";
    runtimeInputs = [appRun];
    text = ''
      if [ "''${HYPR_WL_DEBUG:-0}" = "1" ]; then
        exec app-run -s b -a quickshell ${tracedBar}/bin/qs-bar-traced
      fi

      exec app-run -s b -a quickshell qs -c task-bar
    '';
  };
  # Unattended suspend/resume driver for the same fault; the rate is ~3% per
  # suspend, so hand-run trials are worth almost nothing.
  #
  # runtimeInputs deliberately omits quickshell (it would shadow the profile
  # build, as above) and sudo (the working one is the setuid wrapper in
  # /run/wrappers/bin). hyprctl likewise comes from the session's PATH so it
  # always matches the running compositor.
  suspendRepro = pkgs.writeShellApplication {
    name = "hypr-suspend-repro";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.python3
      pkgs.util-linux # rtcwake
      pkgs.systemd # systemctl, loginctl, journalctl
      pkgs.procps # pgrep
      pkgs.gnugrep
    ];
    text = builtins.readFile ./hypr-suspend-repro.sh;
  };
in {
  options.hyprWlDebug = {
    logFile = lib.mkOption {
      type = lib.types.str;
      default = defaultLog;
      readOnly = true;
      description = ''
        Where the traced session parks the tail of quickshell's WAYLAND_DEBUG
        output. Overridable at runtime with QS_WL_LOG for a one-off run.
      '';
    };
  };

  config = {
    # Consumed by ./hyprland.nix's autostart hook. Same seam as app-run.nix's
    # _module.args.appRun, so the path is resolved hermetically rather than off
    # whatever PATH the compositor happens to have.
    _module.args.qsBarLaunch = barLaunch;

    # qs-wl-ring on PATH as well: it is useful on its own for tracing any
    # client by hand (`WAYLAND_DEBUG=client someapp 2>&1 | qs-wl-ring out.log`).
    home.packages = [wlRing barLaunch suspendRepro];
  };
}
