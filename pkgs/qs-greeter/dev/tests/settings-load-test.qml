import QtQuick
import Quickshell

// Settings.qml and Log.qml are same-directory symlinks to the real
// pkgs/qs-greeter/greeter/ files (see SettingsMerge.js for the same
// technique). Quickshell auto-registers pragma Singleton files that sit next
// to the entrypoint, so they are used bare below, exactly as shell.qml uses
// them -- no import alias, and no copy of the greeter's actual code.
//
// Settings.ready flips asynchronously (it waits on two FileView loads), so
// the checks cannot run straight from Component.onCompleted -- on the first
// pass Settings.ready is still false and every assertion reads the
// not-yet-populated defaults. Wait for readyChanged, with a timer as a
// backstop so a genuinely broken load still prints a result instead of
// hanging.
ShellRoot {
    id: root
    property bool _done: false

    function runChecks() {
        if (_done) return;
        _done = true;
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) { pass++; }
            else console.log("SETTINGS-TEST CASE FAIL: " + name + " got=" + got + " want=" + want);
        }
        // QSG_DEFAULTS / QSG_USER_FILE are set by the runner script below.
        check("ready", Settings.ready, true);
        check("skin", Settings.skinName, "xp");
        check("palette", Settings.palette, "gruvbox");
        check("backdropPath", Settings.backdropPath, "/tmp/qsg-test-backdrops/bliss.jpg");
        console.log("SETTINGS-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }

    Connections {
        target: Settings
        function onReadyChanged() {
            if (Settings.ready) root.runChecks();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: root.runChecks()
    }

    Component.onCompleted: if (Settings.ready) runChecks();
}
