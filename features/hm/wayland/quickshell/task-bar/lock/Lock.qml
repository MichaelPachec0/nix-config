// features/hm/wayland/quickshell/task-bar/lock/Lock.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool locked: false
    property alias context: lockContext
    property var wallpapers: ({}) // screenName -> image path

    function lock() { root.locked = true; }
    function unlock() { root.locked = false; }

    function wallpaperFor(name) {
        return (name && root.wallpapers[name]) ? root.wallpapers[name] : LockConfig.fallbackImage;
    }

    function refreshWallpapers() { awwwProc.running = true; }

    LockContext {
        id: lockContext
        onUnlocked: {
            root.locked = false;                // release the compositor lock
            unlockSessionProc.exec(["loginctl", "unlock-session"]); // fire unlock.target
            lockContext.reset();
        }
    }
    Process { id: unlockSessionProc }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        // One WlSessionLockSurface is created per output automatically.
        surface: WlSessionLockSurface {
            id: surface
            color: "transparent"

            LockSurface {
                anchors.fill: parent
                context: root.context
                backdropSource: root.wallpaperFor(surface.screen ? surface.screen.name : "")
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function unlock(): void { root.unlock(); }
        function toggle(): void { root.locked = !root.locked; }
    }

    // Dev escape: when relaunched by lock-escape.sh (QS_LOCK_ESCAPE=1) and
    // fail-open is enabled, acquire the (stranded) lock then immediately release
    // it, which unlocks the compositor. Requires misc:allow_session_lock_restore.
    Component.onCompleted: {
        if (Quickshell.env("QS_LOCK_ESCAPE") === "1" && LockConfig.failOpenOnCrash) {
            root.locked = true;   // re-acquires the stranded lock (restore)
            releaseTimer.start();
        }
    }
    Timer {
        id: releaseTimer
        interval: 200
        onTriggered: root.locked = false; // unlock_and_destroy -> desktop returns
    }

    // Marker file for the watchdog (qs-lock-watchdog): present while locked, so
    // a poll can tell "locked marker present but quickshell dead" apart from a
    // clean unlocked state. NB: single onLockedChanged handler -- later tasks
    // add more effects here rather than declaring a second one.
    onLockedChanged: {
        markerProc.exec(
            root.locked
            ? ["sh", "-c", "touch \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked\""]
            : ["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked\""]
        );
        if (root.locked) {
            lockContext.reset();
            root.refreshWallpapers();
        }
    }

    Process { id: markerProc }

    // Per-output current wallpaper (LockBackdrop). Refreshed on lock so the
    // backdrop refines from the fallback image to the real wallpaper without
    // any desktop-visible race (locked is already true by then).
    Process {
        id: awwwProc
        command: ["awww", "query"]
        stdout: StdioCollector {
            id: awwwOut
            onStreamFinished: {
                var map = {};
                var re = /^:?\s*(\S+):.*currently displaying:\s*image:\s*(.+)$/;
                var lines = (awwwOut.text || "").split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(re);
                    if (m) map[m[1]] = m[2].trim();
                }
                root.wallpapers = map;
            }
        }
    }
}
