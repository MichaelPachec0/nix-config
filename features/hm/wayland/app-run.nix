# app-run: launch a GUI application in its own systemd scope under uwsm.
#
# WHY THIS EXISTS
# ---------------
# The session is already uwsm-managed (programs.hyprland.withUWSM in
# features/nixos/desktop/wayland, which installs hyprland-uwsm.desktop and runs
# the compositor as wayland-wm@hyprland.desktop.service). But uwsm only manages
# the *session*: anything the compositor `exec`s is a plain fork() of the
# compositor process, so it inherits the COMPOSITOR'S cgroup. Measured before
# this wrapper existed -- kitty, Firefox's content processes and quickshell all
# reported
#
#   session.slice/wayland-wm@hyprland.desktop.service
#
# while app.slice/app-graphical.slice was completely empty. Consequences: one
# runaway app is memory-accounted against (and OOM-killed together with) the
# compositor, no per-app unit to inspect/stop, and `systemctl --user restart`
# on the compositor would take every app with it. Routing launches through a
# uwsm-aware runner re-parents them into
#
#   app.slice/app-graphical.slice/app-<wm>-<name>-<hash>.scope
#
# which is the "fully uwsm" state uwsm's own docs push for ("It would not be
# prudent to accumulate app processes in compositor's unit").
#
# WHY A WRAPPER AND NOT THE RUNNER INLINE
# ---------------------------------------
# One detection rule and one backend choice, in one place. It is reachable from
# every layer that starts an app -- Hyprland binds, the autostart hook, rofi's
# run-command, quickshell, and the hy3-project script -- without each of them
# re-deriving whether uwsm is in play or which runner to call.
#
# WHY app2unit AND NOT `uwsm app`
# -------------------------------
# `uwsm app` is a Python entry point and pays full interpreter startup on every
# launch. Measured on this machine, 15 iterations each:
#
#   uwsm app            241 ms      python startup dominates
#   uwsm-app             27 ms      C client, but see below
#   app2unit             19 ms      pure shell, no daemon
#   runapp (service)     19 ms
#   runapp --scope       10 ms
#   bare exec             2 ms      floor
#
# 241 ms is a visible hitch on every single app launch, so the Python path is
# not viable. Of the three fast options:
#
#   uwsm-app  is a C client for wayland-wm-app-daemon.service, which is
#             on-demand and CollectMode=inactive-or-failed. Whenever the daemon
#             has been collected the next launch pays the cold path -- measured
#             220 ms first call, 24 ms second. That reintroduces exactly the
#             stutter this is meant to remove, unpredictably.
#   runapp    is the fastest but has a different CLI (--slice takes a full unit
#             name, no -a) and no terminal mode, which run-shell-command in
#             ./rofi.nix needs.
#   app2unit  is by uwsm's own author and is a drop-in superset of `uwsm app`:
#             same -s a|b|s / -a / -T / -- surface, and -- verified against
#             --test -- it emits the same unit naming and placement,
#             app.slice/app-graphical.slice/app-Hyprland-<name>-<hash>.scope.
#             Pure shell, so no daemon and no cold path. It also stamps
#             PartOf=graphical-session.target onto the scope as a property, so
#             apps are still torn down with the session.
#
# app2unit's own slice shorthands default to the plain systemd slices
# (a=app.slice), not uwsm's graphical ones, so APP2UNIT_SLICES is set below to
# line them up with what uwsm creates and what nixos/thanatos/memory.nix
# protects.
#
# THE DETECTION RULE
# ------------------
# UWSM_FINALIZE_VARNAMES is exported by `uwsm start` into the compositor's
# environment AND pushed into the systemd user manager by `uwsm finalize`. So
# it is set both for direct compositor children and for processes that are
# already inside a uwsm scope. That second half matters: rofi launched via
# app-run lives in its own scope, and when it in turn calls app-run the chain
# has to keep working. A cgroup-based test ("am I under wayland-wm@?") looks
# more precise but breaks exactly there -- rofi's scope is not under the
# compositor unit, so the app it launches would silently stay parented to
# rofi's transient scope and die when rofi exits. Verified that a nested
# `uwsm app` produces a SIBLING scope under app-graphical.slice, not a child.
#
# ESCAPE HATCH
# ------------
# A hand-launched nested/dev Hyprland inherits UWSM_* from the terminal it was
# started in, so the variable is a false positive there, and launching into the
# session's scopes would hand the window to the OUTER session's Wayland
# display. Start such an instance with APP_RUN_DISABLE=1 (or
# `env -u UWSM_FINALIZE_VARNAMES`) to force the plain-exec path.
#
# WHAT NOT TO WRAP
# ----------------
# Even at app2unit's 19 ms this is a systemd-run round trip per launch, and the
# point of a scope is to hold a long-lived process. One-shot utilities get
# nothing from it and would pay for it on every keypress, so volumectl /
# brightnessctl / playerctl / grim / loginctl and the hyprctl helper scripts
# stay bare `exec`.
{pkgs, ...}: let
  appRun = pkgs.writeShellScriptBin "app-run" ''
    # usage: app-run [-s a|b|s] [-a name] [-T] cmd [args...]
    #   -s  slice: a = app-graphical.slice (default, interactive apps)
    #              b = background-graphical.slice (bars, daemons, agents)
    #              s = session-graphical.slice
    #   -a  override the app name inside the generated unit name
    #   -T  run the command inside a terminal
    slice=a
    name=
    term=
    while [ $# -gt 0 ]; do
      case "$1" in
        -s) slice=$2; shift 2 ;;
        -a) name=$2; shift 2 ;;
        -T) term=1; shift ;;
        --) shift; break ;;
        *)  break ;;
      esac
    done

    [ $# -gt 0 ] || { echo "app-run: no command given" >&2; exit 2; }

    if [ -z "''${APP_RUN_DISABLE:-}" ] && [ -n "''${UWSM_FINALIZE_VARNAMES:-}" ]; then
      # Point app2unit's -s shorthands at the slices uwsm actually creates
      # (its own defaults are the plain app.slice/background.slice/session.slice).
      # Overridable from the environment so a session-wide APP2UNIT_SLICES, or a
      # one-off, still wins.
      APP2UNIT_SLICES="''${APP2UNIT_SLICES:-a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice}"
      export APP2UNIT_SLICES

      # Build the runner's flags in $@ ahead of the command, so an unset -a/-T
      # contributes no argument at all (an empty "" would be read as a command).
      if [ -n "$term" ]; then set -- -T -- "$@"; else set -- -- "$@"; fi
      if [ -n "$name" ]; then set -- -a "$name" "$@"; fi
      exec ${pkgs.app2unit}/bin/app2unit -s "$slice" "$@"
    fi

    # Non-uwsm fallback. app2unit's -T resolves the terminal through
    # xdg-terminal-exec; off the uwsm path there is no session to ask, so fall
    # back to $TERMINAL (set alongside the rest of the session environment, see
    # hyprland.nix sessionEnv) and finally to kitty.
    if [ -n "$term" ]; then
      exec "''${TERMINAL:-kitty}" -e "$@"
    fi
    exec "$@"
  '';
in {
  # Published as a module arg so hyprland.nix / common.nix can reference the
  # absolute store path (store-pinned, no PATH lookup), and installed so
  # everything resolving it from PATH -- rofi's run-command, quickshell,
  # hy3-project -- finds the same script.
  _module.args.appRun = appRun;
  home.packages = [appRun];
}
