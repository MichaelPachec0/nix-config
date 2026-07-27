// features/hm/wayland/quickshell/task-bar/lock/Lock.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "." as Lock

Scope {
    id: root

    property bool locked: false

    function lock() { root.locked = true; }
    function unlock() { root.locked = false; }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        // One WlSessionLockSurface is created per output automatically.
        surface: WlSessionLockSurface {
            id: surface
            color: "#1d2021" // Gruvbox dark bg0_h; replaced by LockBackdrop in Task 4

            Text {
                anchors.centerIn: parent
                text: "task-bar lock (skeleton) -- output: " + (surface.screen ? surface.screen.name : "?")
                color: "#ebdbb2" // Gruvbox fg
                font.pixelSize: 24
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
        if (Quickshell.env("QS_LOCK_ESCAPE") === "1" && Lock.LockConfig.failOpenOnCrash) {
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
    onLockedChanged: markerProc.exec(
        root.locked
        ? ["sh", "-c", "touch \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked\""]
        : ["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked\""]
    )

    Process { id: markerProc }
}
