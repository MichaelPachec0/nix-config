# A second Hyprland greeter entry that turns Wayland tracing on.
#
# It has to be a session rather than a rebuild flag: the failure being chased
# (the quickshell bar disappearing on resume) is a compositor-posted protocol
# error, not a crash, so Qt's Wayland plugin _exit(1)s with no coredump and no
# log naming the offending interface. Catching it needs WAYLAND_DEBUG on the
# shell, which costs a formatted line per request and is not acceptable in the
# normal session, plus a real suspend/resume that may be days away. Picking it
# at login means no rebuild to start or stop tracing.
#
# Nothing about the session is restated here. Both desktop files are the stock
# ones out of the Hyprland package, copied with the smallest possible edit: the
# compositor entry gets its Exec prefixed by a wrapper, and the uwsm session
# entry gets Name= changed and its compositor-entry argument repointed. So a
# change to the launcher, its flags or uwsm's arguments flows through untouched.
# Every assumption those edits rest on is asserted in the builder, because a
# debug session that has silently become either broken or identical to the
# normal one would read as "the bug did not reproduce".
#
# The Hyprland config cannot drift either: there is only one, and as of
# 2026-08-16 it makes NO difference between the two sessions at all.
# debug.disable_logs used to be gated on HYPR_WL_DEBUG so only this session got
# Hyprland's own logs; that gate meant a protocol-error death in the normal
# session could not be attributed to an interface, which cost two
# investigations, so ../../../hm/wayland/hyprland.nix now sets it false
# unconditionally. Both sessions therefore get compositor logging.
#
# What this session still buys, and the only thing it buys:
# ../../../hm/wayland/hypr-wl-debug.nix reads HYPR_WL_DEBUG and starts the bar
# under WAYLAND_DEBUG=client with the output ring-buffered -- a line per
# Wayland request and event, which names the offending object rather than only
# the interface. That is the expensive half and stays opt-in at login.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprlandWlDebug;

  # Taken from the package rather than a hand-written path, so "is this the same
  # compositor the normal session runs?" is true by construction.
  hyprPkg = config.programs.hyprland.package;

  # Sets the debug variables and execs its arguments, so it never needs updating
  # when the thing it fronts changes. Two variables because they cost very
  # differently and are useful apart: HYPR_WL_DEBUG buys the protocol trace and
  # Hyprland's own logs (a line per Wayland request), QS_LOCK_DEBUG buys the
  # lock backdrop's capture diagnostics (six lines per lock, see
  # ../../../hm/wayland/quickshell/task-bar/lock/Lock.qml).
  #
  # THE NAME IS LOAD-BEARING -- it must stay `start-hyprland`. uwsm picks its
  # quirks plugin from basename(cmdline[0]), not from the desktop entry or -D
  # names, and splicing a wrapper in front of Exec= makes the wrapper cmdline[0].
  # A wrapper named anything else matches no plugin, `quirks_hyprland` never
  # runs, and three things break silently: UWSM_FINALIZE_VARNAMES is never set,
  # so ../../../hm/wayland/app-run.nix degrades to a plain `exec "$@"` and the
  # bar loses its scope, slice and memory.low protection; `uwsm finalize` never
  # exports HYPRLAND_INSTANCE_SIGNATURE, HYPRCURSOR_* or XCURSOR_*; and uwsm
  # never waits for the compositor to publish the instance signature. That first
  # one already bit once, when a home-manager switch killed the bar because its
  # unplaced relaunch had landed in qs-lock-watchdog.service's cgroup.
  #
  # `start-hyprland` is the name uwsm ships a plugin for; the builder asserts
  # the plugin still exists.
  envWrapper = pkgs.writeShellApplication {
    name = "start-hyprland";
    text = ''
      export HYPR_WL_DEBUG=1
      export QS_LOCK_DEBUG=1
      exec "$@"
    '';
  };

  session =
    pkgs.runCommand "hyprland-wldebug-session" {
      passthru.providedSessions = ["hyprland-wldebug-uwsm"];
    } ''
      comp="${hyprPkg}/share/wayland-sessions/hyprland.desktop"
      sess="${hyprPkg}/share/wayland-sessions/hyprland-uwsm.desktop"

      # --- what the rewrites below assume ---------------------------------
      # One Exec= line each. A second one (an action group, say) would leave
      # the debug session running an untraced compositor.
      [ "$(grep -c '^Exec=' "$comp")" = 1 ]
      [ "$(grep -c '^Exec=' "$sess")" = 1 ]

      # Zero occurrences means upstream stopped launching Hyprland through a
      # desktop entry and this approach needs rethinking; more than one makes
      # the substitution below ambiguous.
      [ "$(grep '^Exec=' "$sess" | grep -c 'hyprland\.desktop')" = 1 ]

      # qs-greeter's sessions-parse.sh builds argv with a bare `split(" ")`, so
      # a quoted argument would be shredded into separate argv entries and the
      # session would fail to launch with no useful error.
      if grep '^Exec=' "$sess" | grep -q '"'; then
        echo "stock hyprland-uwsm.desktop Exec now contains quotes; the greeter cannot parse those" >&2
        exit 1
      fi

      # The plugin the wrapper name resolves to; see envWrapper above.
      [ -f "${config.programs.uwsm.package}/share/uwsm/plugins/start_hyprland.sh" ]

      mkdir -p "$out/share/wayland-sessions"

      sed -e "s|^Exec=|Exec=${envWrapper}/bin/start-hyprland |" \
        "$comp" > "$out/share/wayland-sessions/hyprland-wldebug.desktop"

      sed -e 's|^Name=.*|Name=Hyprland (UWSM, Wayland debug)|' \
        -e 's|^Comment=.*|Comment=Hyprland with compositor logging on and the quickshell bar traced under WAYLAND_DEBUG=client|' \
        -e '/^Exec=/ s|hyprland\.desktop|hyprland-wldebug.desktop|' \
        "$sess" > "$out/share/wayland-sessions/hyprland-wldebug-uwsm.desktop"

      # Both edits must have landed. Emitting a debug session that is byte-wise
      # the normal one is the single worst outcome here -- it would look like
      # "the bug did not reproduce".
      grep -qF "${envWrapper}/bin/start-hyprland" "$out/share/wayland-sessions/hyprland-wldebug.desktop"
      grep -q 'hyprland-wldebug\.desktop' "$out/share/wayland-sessions/hyprland-wldebug-uwsm.desktop"
    '';
in {
  options.programs.hyprlandWlDebug = {
    enable =
      lib.mkEnableOption "a second Hyprland greeter entry with Wayland protocol tracing"
      // {
        default = config.programs.hyprland.enable && config.programs.uwsm.enable;
      };
  };

  config = lib.mkIf cfg.enable {
    # BOTH registrations are needed; neither substitutes for the other.
    # sessionPackages is canonical but puts nothing in /run/current-system/sw --
    # the display-manager module lndir's it into a separate sessionData.desktops
    # path reachable only via environment.sessionVariables.XDG_DATA_DIRS -- and
    # the qs-greeter wrapper reads /run/current-system/sw/share/wayland-sessions,
    # which is why every session that does show up also sits in systemPackages.
    # systemPackages is likewise what lets uwsm resolve the compositor entry by
    # ID, since that path is on XDG_DATA_DIRS unconditionally.
    services.displayManager.sessionPackages = [session];
    environment.systemPackages = [session];
  };
}
