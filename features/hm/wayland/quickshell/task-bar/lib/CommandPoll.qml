import QtQuick
import Quickshell.Io

// Runs `command` (an argv array) every `interval` ms while `running`, parses its
// stdout through `parse`, and exposes the result as `value`. Used for hub state
// that has no native Quickshell service (brightness, nmcli/rfkill, etc.).
//
// `updated()` fires only when the poll produced something new:
//   - A NONZERO exit is treated as a failed poll: value/text are left untouched
//     so a transient hiccup (nmcli/ip during a rekey, a script that momentarily
//     errors) keeps the last-good reading instead of blanking the widget.
//   - Identical stdout to the previous successful run is skipped, so a poller
//     whose output is stable doesn't re-emit every tick and churn downstream
//     bindings/models. (Everything below reads the collector + exit code in
//     onExited -- verified to hold the complete stdout there, even for ~300KB.)
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
    // Set once the first successful poll has emitted, so the dedup below never
    // suppresses the very first reading (even when it is empty).
    property bool _primed: false

    signal updated

    function poll() {
        if (!root.running)
            return;
        if (root.busy)
            return;
        if (!command || command.length === 0)
            return;
        root.busy = true;
        root.watchdog.restart(); // arm: a hung child gets killed at interval*3
        proc.exec(command);
    }

    property Process proc: Process {
        stdout: StdioCollector {
            id: stdoutCollector
        }
        onExited: function (code, status) {
            root.busy = false;
            root.watchdog.stop(); // completed in time -> disarm
            if (code !== 0)
                return; // failed poll (incl. watchdog kill) -> keep last-good value/text
            var out = stdoutCollector.text ?? "";
            if (root._primed && out === root.text)
                return; // unchanged output -> nothing to re-emit
            root._primed = true;
            root.text = out;
            root.value = root.parse(out);
            root.updated();
        }
    }

    property Timer timer: Timer {
        interval: Math.max(50, root.interval)
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    // Watchdog: if a child overruns interval*3 without exiting (a hung nmcli/ip
    // or a wedged script), terminate it so busy clears via onExited and polling
    // resumes -- otherwise busy stays true forever and the poller freezes.
    // Armed on each poll() start, disarmed on exit.
    property Timer watchdog: Timer {
        interval: Math.max(1000, root.interval * 3)
        repeat: false
        onTriggered: if (root.busy) root.proc.running = false
    }
}
