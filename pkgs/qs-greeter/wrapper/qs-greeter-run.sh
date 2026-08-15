#!/usr/bin/env bash
# Greeter entry point, exec'd by the greeter compositor.
#
# Owns three things quickshell cannot do for itself:
#   1. logging (file + journal, pruned)
#   2. crash-loop detection with a fallback that refuses to exit
#   3. building the session list before the UI starts
#
# The crash counter lives in a tmpfs state dir on purpose. It must survive
# greetd restarting the whole compositor (that is the loop being caught) but
# reset on reboot (a reboot is a deliberate retry).
set -uo pipefail

state_dir="${QSG_STATE_DIR:-/run/qs-greeter}"
log_dir="${QSG_LOG_DIR:-/var/log/qs-greeter}"
log_keep="${QSG_LOG_KEEP:-10}"
log_args="${QSG_LOG_ARGS:-}"
journal="${QSG_JOURNAL:-1}"
threshold="${QSG_THRESHOLD:-3}"
window="${QSG_WINDOW:-120}"
config="${QSG_CONFIG:?QSG_CONFIG (greeter QML path) required}"
sessions_dir="${QSG_SESSIONS_DIR:-/run/current-system/sw/share/wayland-sessions}"
filter="${QSG_FILTER:-uwsm}"
extra_json="${QSG_EXTRA_JSON:-[]}"
shells_json="${QSG_SHELLS_JSON:-[]}"
tty_hint="${QSG_TTY_HINT:-2}"
show_log="${QSG_SHOW_LOG:-1}"

# Test seams. In production these stay at their defaults.
now="${QSG_NOW:-$(date +%s)}"
qs_cmd="${QSG_QS_CMD:-}"
fallback_cmd="${QSG_FALLBACK_CMD:-}"
# QSG_PARSE lets a packaged wrapper (writeShellApplication installs this
# script alone in a bin/ directory, so dirname "$0" no longer finds a
# sessions-parse.sh next to it) point at the real location without editing
# this file.
parse_cmd="${QSG_PARSE:-$(dirname "$0")/sessions-parse.sh}"

mkdir -p "$state_dir" "$log_dir"
crashes="$state_dir/crashes"
touch "$crashes"

# --- crash-loop accounting -------------------------------------------------
recent=0
if [ -s "$crashes" ]; then
  while IFS= read -r stamp; do
    [ -n "$stamp" ] || continue
    if [ $((now - stamp)) -le "$window" ]; then
      recent=$((recent + 1))
    fi
  done <"$crashes"
fi

if [ "$recent" -ge "$threshold" ]; then
  echo "qs-greeter: $recent starts within ${window}s, engaging fallback" >&2
  newest="$(find "$log_dir" -name 'greeter-*.log' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n1 | cut -d' ' -f2-)"
  msg="The graphical greeter failed to start $recent times."
  msg="$msg Press Ctrl+Alt+F$tty_hint for a text login. Logs: $log_dir"

  if [ -n "$fallback_cmd" ]; then
    # test seam
    eval "$fallback_cmd"
  else
    if [ "$show_log" = "1" ] && [ -n "$newest" ]; then
      foot --title "qs-greeter log" -- \
        sh -c "tail -n 200 '$newest'; echo; echo 'Press Ctrl+Alt+F$tty_hint for a text login.'; read -r _" &
    fi
    swaynag -t error -m "$msg" \
      -b 'Reboot' 'systemctl reboot' \
      -b 'Power off' 'systemctl poweroff' || true
    # Block instead of exiting: returning control to greetd restarts the
    # compositor and re-enters the loop. Sway stays up, so the VT switch
    # promised in the message keeps working.
    while :; do sleep 3600; done
  fi
  exit 0
fi

printf '%s\n' "$now" >>"$crashes"

# --- session list ----------------------------------------------------------
sessions_out="$state_dir/sessions.json"
if ! "$parse_cmd" \
      "$sessions_dir" "$filter" "$extra_json" "$shells_json" >"$sessions_out"; then
  echo "qs-greeter: session list generation failed" >&2
  echo '[]' >"$sessions_out"
fi

# --- logging ---------------------------------------------------------------
log_file="$log_dir/greeter-$now.log"
# Prune oldest first, keeping log_keep including the file about to be written.
mapfile -t old < <(find "$log_dir" -name 'greeter-*.log' -printf '%T@ %p\n' 2>/dev/null \
  | sort -n | head -n -$((log_keep - 1)) | cut -d' ' -f2-)
for f in "${old[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done

# --- Qt environment hygiene ------------------------------------------------
# greetd sources /etc/profile for the greeter session (source_profile,
# documented as defaulting to true in greetd.5), and NixOS's /etc/profile
# sources /etc/set-environment -- so the host's entire environment.variables
# set arrives here, chosen for the logged-in user's desktop and never for a
# greeter. QT_QPA_PLATFORMTHEME is the one that is fatal rather than merely
# wrong: with qt.platformTheme = "gtk2" (or "gtk3") Qt loads a platform theme
# plugin that links GTK and calls gtk_init(), and gtk_init() -- unlike
# gtk_init_check() -- prints "cannot open display:" and calls exit(1) on the
# whole process when no X display exists. The greeter compositor runs
# "xwayland disable", so one never does.
#
# That failure is close to invisible, which is why it is unset here rather
# than worked around later: a clean exit(1) leaves no coredump, so it does not
# look like a crash; and by that point quickshell's threaded logger has
# switched to a queued event-loop connection, so everything it logs from there
# on waits for QGuiApplication::exec() to flush it -- which a process dying
# inside the QGuiApplication constructor never reaches. GTK's own warning goes
# straight to stderr, bypassing Qt's logger entirely, and is the only evidence
# that survives.
#
# Neither variable has anything to offer this program: the greeter renders its
# own skin with its own palette and uses no platform palette, no native
# dialogs and no widget style. ReGreet never tripped over this because it is
# GTK4 and ignores both.
unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE

# Refuse to silently fall back to xcb for the same reason -- on a greeter with
# no xwayland, an X11 fallback can only fail, and failing loudly as "wayland
# platform unavailable" beats failing as a GTK warning about a display nobody
# asked for. Defaulted rather than forced so the headless dev suites can still
# ask for offscreen.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

# --- run -------------------------------------------------------------------
# shellcheck disable=SC2086
if [ -n "$qs_cmd" ]; then
  set -- $qs_cmd
else
  set -- qs -p "$config" --no-color $log_args
fi

if [ "$journal" = "1" ]; then
  "$@" 2>&1 | tee -a "$log_file" | systemd-cat -t qs-greeter
else
  "$@" 2>&1 | tee -a "$log_file"
fi
status="${PIPESTATUS[0]}"

if [ "$status" = "0" ]; then
  # Session launched. Clear the counter so an unrelated crash weeks later
  # starts from zero.
  : >"$crashes"
fi
exit "$status"
