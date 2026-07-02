import QtQuick
import Quickshell
import Quickshell.Io

// Shared, disk-persisted calendar UI state. One instance lives at ShellRoot
// (outside Variants) so every monitor's date widget reads/writes the same value
// live, and it survives a quickshell restart. Uses the repo's FileView idiom
// (see lib/ThemeEngine.qml). A one-shot mkdir -p guarantees the state dir exists
// before the first writeAdapter() (FileView does not create parent dirs).
Scope {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell"
    property alias layout: adapter.layout // 0=single, 1=three, 2=year

    Process {
        running: true
        command: ["mkdir", "-p", root.dir]
    }

    FileView {
        id: file
        path: root.dir + "/calendar.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: reload()

        JsonAdapter {
            id: adapter
            property int layout: 0
        }
    }
}
