// features/hm/wayland/quickshell/task-bar/lock/LockSecurityState.qml
// Persisted lock-security facts -- currently just the last successful unlock, in
// epoch ms. Writable state OUTSIDE the ~/.config/quickshell repo symlink,
// mirroring lock/LockClockState.qml.
//
// This has to be persisted rather than a plain property: "last unlock" only
// means anything if it survives a quickshell restart, which is exactly the case
// where a property would silently reset to "never".
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property string dir: (Quickshell.env("HOME") || "") + "/.local/state/quickshell"
    property alias lastUnlockMs: adapter.lastUnlockMs

    Process { running: true; command: ["mkdir", "-p", root.dir] }

    FileView {
        id: file
        path: root.dir + "/lock-security.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: reload()
        JsonAdapter { id: adapter; property double lastUnlockMs: 0 }
    }
}
