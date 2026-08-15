pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Read from the LED sysfs node rather than a compositor API so it behaves
// identically under the greeter's sway and under a nested test compositor.
Singleton {
    id: root
    property bool on: false

    Process {
        id: probe
        command: ["sh", "-c",
            "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -rn | head -n1"]
        stdout: SplitParser {
            onRead: function (line) { root.on = parseInt(line, 10) > 0; }
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: probe.running = true
    }
}
