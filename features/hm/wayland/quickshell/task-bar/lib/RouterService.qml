import QtQuick
import Quickshell
import Quickshell.Io

// Reads the hardened poll service's artifact and exposes it as properties.
// Instantiate INSIDE the per-screen Variants Scope (like Lib.CalState) so the
// binding resolves across the Variants delegate. Holds no secrets; the only
// write path is reconnect(), which starts a polkit-gated systemd unit.
Scope {
    id: root

    // Path to the poll service's artifact. Overridable so an offline harness can
    // point it at a fixture; production leaves the default.
    property string statusPath: "/run/e5800/status.json"

    property var data: ({})
    readonly property bool reachable: root.data.reachable === true
    // Reachable but SSH key rejected (e.g. router factory-reset) -> prompt re-auth.
    readonly property bool authError: root.data.auth_error === true
    readonly property var cellular: root.data.cellular || ({})
    readonly property var battery: root.data.battery || ({})
    readonly property var uplink: root.data.uplink || ({})
    readonly property var clients: root.data.clients || ({})
    readonly property var wifi: root.data.wifi || []
    readonly property var vpn: root.data.vpn || ({})
    readonly property var system: root.data.system || ({})
    readonly property var dataUsage: root.data.data || ({})
    readonly property var throughput: root.data.throughput || ({})
    readonly property var device: root.data.device || ({})

    // recovering = service marker OR local optimistic latch (set on click,
    // auto-dropped after a safety window past the service timeout).
    property bool _latch: false
    readonly property bool recovering: (root.data.recovery && root.data.recovery.active === true) || root._latch

    Timer {
        id: latchTimer
        interval: 130000
        onTriggered: root._latch = false
    }

    function reconnect(action) {
        root._latch = true;
        latchTimer.restart();
        starter.exec(["systemctl", "start", "e5800-" +
            (action === "reboot" ? "reboot-modem" : action) + ".service"]);
    }

    Process { id: starter }

    FileView {
        id: file
        path: root.statusPath
        watchChanges: true
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
}
