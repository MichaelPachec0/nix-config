# Dev escape hatch: return the session to UNLOCKED, whatever the lock's state.
# 1) graceful IPC unlock if the shell is alive; 2) else relaunch the shell with
# QS_LOCK_ESCAPE=1 so Lock.qml acquires-then-releases the stranded lock
# (requires misc:allow_session_lock_restore = true).
# NB: packaged via writeShellApplication, which injects the shebang and
# `set -euo pipefail` and runs shellcheck -- so no shebang here, and guard
# commands that may exit non-zero (pkill with no match) with `|| true`.

CFG="task-bar"

if qs -c "$CFG" ipc call lock unlock 2>/dev/null; then
    exit 0
fi

# Shell unresponsive/dead: ensure it is gone, then relaunch in escape mode.
# Match the wrapped bar by cmdline: its comm is truncated to
# `.quickshell-wra`, so `-x quickshell` never matches. `-f` on the full
# `quickshell -c task-bar` command line is comm-truncation-proof.
pkill -f 'quickshell -c task-bar' 2>/dev/null || true
sleep 0.3
QS_LOCK_ESCAPE=1 qs -c "$CFG" >/dev/null 2>&1 &
exit 0
