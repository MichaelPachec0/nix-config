// features/hm/wayland/quickshell/task-bar/lock/LockClockState.qml
// Persisted lock-screen clock mode (false = 24h, true = 12h), toggled by clicking
// the clock. Writable state OUTSIDE the ~/.config/quickshell repo symlink, mirroring
// lib/CalState.qml. Auto-persists on each single-property write.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property string dir: (Quickshell.env("HOME") || "") + "/.local/state/quickshell"
    property alias hour12: adapter.hour12

    Process { running: true; command: ["mkdir", "-p", root.dir] }

    FileView {
        id: file
        path: root.dir + "/lock-clock.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: reload()
        JsonAdapter { id: adapter; property bool hour12: false }
    }
}
