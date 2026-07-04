import QtQuick
import Quickshell.Io

// Runs `command` (an argv array) every `interval` ms while `running`, parses its
// stdout through `parse`, and exposes the result as `value` -- emitting
// `updated()` only when the parsed value actually changes. Used for hub state
// that has no native Quickshell service (brightness, nmcli/rfkill, etc.).
QtObject {
    id: root

    property int interval: 1000
    property var command: []
    property var parse: function (out) {
        return String(out ?? "").trim();
    }
    property bool running: true
    property var value: null
    property string text: ""
    property bool busy: false

    signal updated

    function poll() {
        if (!root.running)
            return;
        if (root.busy)
            return;
        if (!command || command.length === 0)
            return;
        root.busy = true;
        proc.exec(command);
    }

    property Process proc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.text = this.text ?? "";
                var parsed = root.parse(root.text);
                if (parsed !== root.value) {
                    root.value = parsed;
                    root.updated();
                }
                root.busy = false;
            }
        }
        onExited: root.busy = false
    }

    property Timer timer: Timer {
        interval: Math.max(50, root.interval)
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: root.poll()
    }
}
