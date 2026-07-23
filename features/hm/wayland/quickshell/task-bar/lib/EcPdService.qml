import QtQuick
import Quickshell
import Quickshell.Io

// Host-side USB-C charger/PD state from /run/ec-pd/status.json (written by the
// root ec-pd-poll service, which decodes the EC RAM -- UCSI is dead on this
// laptop). Mirrors RouterService.qml: FileView + a periodic reload (the service
// rewrites the file atomically, which breaks a plain watch, and it may not exist
// at bar start). Hoisted to ShellRoot; passed by reference as ecPdSvc -> the
// Taskbar `ecPd` property. The ShellRoot id MUST differ from that property name
// (Variants delegate shadowing -- see the shell.qml submapSvc note).
Scope {
    id: root

    property string statusPath: "/run/ec-pd/status.json"
    property var data: ({})

    readonly property bool present: root.data.present === true
    readonly property bool pd: root.data.pd === true
    readonly property int watts: root.data.watts || 0
    readonly property bool cableLimited: root.data.cableLimited === true
    // "PD, 100 W" / "PD, 60 W (3A cable)" / "non-PD 5 V" / "" (nothing attached)
    readonly property string label: !root.present ? ""
        : (root.pd ? ("PD, " + root.watts + " W" + (root.cableLimited ? " (3A cable)" : ""))
                   : "non-PD 5 V")

    FileView {
        id: file
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        Component.onCompleted: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(file.text());
            } catch (e) {
                root.data = {};
            }
        }
    }
    Timer {
        running: true
        interval: 2000
        repeat: true
        onTriggered: file.reload()
    }
}
