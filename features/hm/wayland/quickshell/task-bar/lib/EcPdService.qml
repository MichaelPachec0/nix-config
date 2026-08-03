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
    // watts (0xC9) is the charger/cable/port CAPABILITY, which can exceed what
    // the laptop draws. The P14s Gen1 PD sink caps at 65 W, so the negotiated
    // (and metered) power is min(capability, 65) -- e.g. a 100 W charger -> 65 W.
    readonly property int watts: root.data.watts || 0
    readonly property int negotiated: Math.min(root.watts, 65)
    // "PD, 65 W" / "non-PD 5 V" / "" (nothing attached). NOTE: the ec-pd JSON also
    // carries cableLimited (0x2F bit6), but that byte proved an unreliable "3A
    // cable" signal (set even on a full 100 W/3.25 A/5A-capable link), so it is
    // deliberately NOT surfaced here.
    readonly property string label: !root.present ? ""
        : (root.pd ? ("PD, " + root.negotiated + " W")
                   : "non-PD 5 V")

    // Whether the status file is actually there. Drives the poll cadence below
    // only -- `present` above is a different question (is a charger attached).
    property bool _fileSeen: false

    FileView {
        id: file
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        Component.onCompleted: reload()
        onLoadFailed: root._fileSeen = false
        onLoaded: {
            try {
                root.data = JSON.parse(file.text());
            } catch (e) {
                root.data = {};
            }
            // The file EXISTING is the signal, not whether it parsed -- same
            // reasoning as RouterService.statusSeen.
            root._fileSeen = true;
        }
    }
    // The poll service rewrites status.json atomically (temp + rename), which
    // breaks a plain file watch, and the file may not exist when the bar starts.
    // So this reload is a poll, not a redundant second watcher.
    //
    // It is however absent *indefinitely* wherever the producer is off, which is
    // the default: services.ecPd is disabled (flake.nix) because polling EC RAM
    // storms the EC's GPE and starves the keyboard matrix. Re-arming a 2s reload
    // forever against a path that will never appear is pure waste, so back off
    // while it is missing; the service cadence resumes the moment it loads.
    Timer {
        running: true
        interval: root._fileSeen ? 2000 : 30000
        repeat: true
        onTriggered: file.reload()
    }
}
