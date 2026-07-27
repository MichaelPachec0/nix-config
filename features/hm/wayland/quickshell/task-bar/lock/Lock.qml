// features/hm/wayland/quickshell/task-bar/lock/Lock.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

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
}
