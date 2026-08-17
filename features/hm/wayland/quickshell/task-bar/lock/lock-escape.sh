# Dev escape hatch: return the session to UNLOCKED, whatever the lock's state.
# 1) if the shell is alive, drive it over IPC to acquire-then-release the lock;
# 2) else relaunch the shell with QS_LOCK_ESCAPE=1 so Lock.qml does the same
# from Component.onCompleted. Both paths need misc:allow_session_lock_restore,
# because reclaiming a lock whose original client is gone IS a restore.
# NB: packaged via writeShellApplication, which injects the shebang and
# `set -euo pipefail` and runs shellcheck -- so no shebang here, and guard
# commands that may exit non-zero (pkill with no match) with `|| true`.

CFG="task-bar"

# Re-read the session's live environment instead of trusting what we inherited.
#
# A systemd unit's PROCESS environment is captured once, when the unit starts.
# uwsm publishes WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE into the user
# MANAGER's environment at finalize time, so a unit that started before that
# keeps an environment with no display in it for the rest of the session.
# qs-lock-watchdog.service lost exactly that race on 2026-08-16 (unit started
# 23:29:34, the same second as uwsm's env-preloader) and carried 44 vars with
# no WAYLAND_DISPLAY. The relaunch below inherited that, Qt fell back to the
# xcb platform plugin, found no X server, and died with "no Qt platform plugin
# could be initialized" -- two coredumps and a session left with no bar, from
# the recovery path that exists to prevent exactly that.
#
# Reading the manager's environment here is immune to unit start order, which
# is the actual defect. Explicit per-variable assignment rather than eval of
# the whole block: show-environment emits $'...' shell quoting for values that
# need it, and blindly exporting those would set the literal text.
live_env() {
    # Trailing `|| true` is load-bearing: writeShellApplication runs this under
    # `set -euo pipefail`, so a systemctl that cannot reach the user manager
    # would abort lock-escape right here -- silently, and before the explicit
    # refusal below could say why.
    systemctl --user show-environment 2>/dev/null | sed -n "s/^$1=//p" | head -1 || true
}

for _var in WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR; do
    _val="$(live_env "$_var")"
    if [ -n "$_val" ]; then
        case "$_var" in
            WAYLAND_DISPLAY) export WAYLAND_DISPLAY="$_val" ;;
            HYPRLAND_INSTANCE_SIGNATURE) export HYPRLAND_INSTANCE_SIGNATURE="$_val" ;;
            XDG_RUNTIME_DIR) export XDG_RUNTIME_DIR="$_val" ;;
        esac
    fi
done
unset _var _val

# Without a display there is nothing to unlock and a relaunch would only
# reproduce the abort above. Fail loudly rather than leaving a silent crash
# loop in the journal.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "lock-escape: no WAYLAND_DISPLAY in this process or in the systemd user environment; refusing to relaunch" >&2
    exit 1
fi

# ACQUIRE, THEN RELEASE -- releasing alone is not enough, and that is what
# left the session stranded on 2026-08-16.
#
# The compositor's ext_session_lock outlives the client that took it. When the
# shell dies while holding the lock, Hyprland keeps showing its solid-colour
# fallback and a NEW shell does not inherit that lock -- it simply starts up
# unlocked, holding nothing. A bare `unlock` then reports success (there is
# nothing for it to do) while the screen stays stuck, and this script exited 0
# believing it had recovered. Verified live: with the fallback on screen and a
# healthy bar running, `call lock unlock` returned success and changed
# nothing; `call lock lock` followed by `call lock unlock` cleared it. The
# `lock` re-acquires the stranded lock into the live client (a session-lock
# restore, which is why misc:allow_session_lock_restore must be true) and the
# `unlock` then destroys it properly. That is the same acquire-then-release
# the QS_LOCK_ESCAPE relaunch below performs; doing it over IPC just avoids
# restarting a perfectly healthy shell.
#
# Address the shell by PID, not by `-c "$CFG"`. Dead instances leave their
# entries under $XDG_RUNTIME_DIR/quickshell/by-pid, and once more than one is
# registered for a config name `ipc call` refuses to pick and prints the
# candidate list instead of acting -- observed with four stale entries.
shell_pid="$(pgrep -f "quickshell -c $CFG" | head -1 || true)"

if [ -n "$shell_pid" ] \
    && qs ipc --pid "$shell_pid" call lock lock >/dev/null 2>&1 \
    && sleep 0.3 \
    && qs ipc --pid "$shell_pid" call lock unlock >/dev/null 2>&1; then
    exit 0
fi

# Shell unresponsive/dead: ensure it is gone, then relaunch in escape mode.
# Match the wrapped bar by cmdline: its comm is truncated to
# `.quickshell-wra`, so `-x quickshell` never matches. `-f` on the full
# `quickshell -c task-bar` command line is comm-truncation-proof.
pkill -f 'quickshell -c task-bar' 2>/dev/null || true
sleep 0.3
# Same placement as the autostart hook (hyprland.nix): -s b ASKS for
# background-graphical.slice so the recovered bar keeps the memory.low
# protection the normally-started one gets (nixos/thanatos/memory.nix).
#
# Do not assume it lands there. app-run only takes its uwsm branch when
# UWSM_FINALIZE_VARNAMES is set, and that comes from uwsm's per-compositor
# quirks plugin, which uwsm selects by basename(Exec[0]) -- so a session
# launched through a wrapper gets no plugin, no variable, and app-run silently
# degrades to plain `exec "$@"`. When that happened the recovered bar simply
# inherited THIS script's cgroup, i.e. qs-lock-watchdog.service, and a
# home-manager switch restarting that unit killed the bar with it
# (KillMode=control-group). Fixed at the source in
# ../../../../../nixos/desktop/wayland/hyprland-wldebug.nix by naming the
# wrapper start-hyprland, but the degradation is silent, so treat placement
# here as best-effort rather than guaranteed.
# app2unit uses `systemd-run --scope`, which execs in place, so QS_LOCK_ESCAPE
# is inherited by the scope -- the whole point of this relaunch. The scope name
# carries a random suffix, so it cannot collide with a stale one.
QS_LOCK_ESCAPE=1 app-run -s b -a quickshell qs -c "$CFG" >/dev/null 2>&1 &
exit 0
