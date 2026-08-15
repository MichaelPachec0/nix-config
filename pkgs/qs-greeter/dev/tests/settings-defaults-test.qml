import QtQuick
import Quickshell

// Asserts the Nix-defaults-only merge result (skin=xp, palette=luna, no
// backdrop image). Used by the runner for two different scenarios that
// share the same expected outcome but must differ in whether a warning was
// logged: a missing user file (first boot -- must be silent) and a corrupt
// user file (must warn, then fall back). Warning presence/absence is
// asserted by the runner against qs's combined output, not here -- this
// file only proves Settings.qml actually reaches ready=true with the
// defaults intact in both cases; SettingsMerge.js's own fallback logic
// already has full coverage in merge-test.qml.
//
// Same-directory Log.qml/Settings.qml symlinks as settings-load-test.qml
// resolve the singletons; see that file's header comment for why a
// directory-crossing import does not work under `qs -p`.
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
        check("ready", Settings.ready, true);
        check("skin", Settings.skinName, "xp");
        check("palette", Settings.palette, "luna");
        check("backdropPath", Settings.backdropPath, "");
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
