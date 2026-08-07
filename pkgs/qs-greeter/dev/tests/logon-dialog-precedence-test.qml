import QtQuick
import Quickshell
import "xp-kit" as XpKit
import "xp-kit/screens" as XpScreens

// Companion to logon-dialog-test.qml, split out because these two things
// each need a DIFFERENT global Settings/GreeterState fixture than the main
// test's (Settings and GreeterState are singletons -- only one fixture
// combination can be live per process):
//
//   1. session default-selection precedence: combo selection (none here,
//      untouched) > Settings.config.sessions.default > GreeterState.
//      lastSession > first entry. Driven twice by the runner with
//      different defaults.json/state.json pairs (QSG_TEST_EXPECT_PRESELECT
//      says which entry this run's fixtures should resolve to).
//   2. Options only reveals the session row when Settings.config.
//      sessions.picker is true (QSG_TEST_PICKER_OFF=1 flips this run to
//      the picker-disabled fixture and asserts toggleOptions() is a no-op).
//
// The readiness gate below reads Settings via XpScreens.Settings, not the
// bare Settings this file also has its own local symlink for: Quickshell
// mints an INDEPENDENT singleton instance per directory even when the
// symlinks resolve to the same real file (confirmed empirically -- see
// logon-dialog-test.qml's Caps Lock block for the two-directory repro), so
// a bare `Settings.ready` here would be a different object than the one
// LogonDialog.qml (loaded through xp-kit/screens/) actually reads
// Settings.config from. Sessions.ready is read bare because Sessions IS
// the same instance dlg.sessions holds -- it is passed down as a prop
// below, an actual object reference, not a fresh per-directory lookup.
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0

    function check(name, got, want) {
        total++;
        if (got === want) pass++;
        else console.log("LOGON-PRECEDENCE-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
    }

    MockBackend { id: mock }
    XpKit.Theme { id: theme }

    XpScreens.LogonDialog {
        id: dlg
        theme: theme
        session: Session
        sessions: Sessions
    }

    Component.onCompleted: {
        Session.backend = mock;

        var t = Qt.createQmlObject('import QtQuick; Timer { interval: 20; repeat: true }', root);
        var start = Date.now();
        t.triggered.connect(function () {
            var settled = Sessions.ready === true && XpScreens.Settings.ready === true;
            if (!settled && Date.now() - start <= 2000) return;
            t.stop(); t.destroy();

            if (!settled) {
                check("settledTimeout", "timed-out", "settled");
            } else {
                var expectPreselect = Quickshell.env("QSG_TEST_EXPECT_PRESELECT") || "";
                var pickerOff = Quickshell.env("QSG_TEST_PICKER_OFF") === "1";

                if (expectPreselect) {
                    check("preselectMatchesExpectedPrecedence", dlg.testComboCurrentName, expectPreselect);
                }

                // F5: optionsExpanded must initialize from
                // Settings.config.optionsExpanded, read BEFORE the
                // toggleOptions() call below -- that call assigns
                // dlg.optionsExpanded directly, which permanently tears
                // down whatever declarative binding it started with
                // (standard QML behavior for a property that had one), so
                // this is the only point in this dlg instance's lifetime
                // where the INITIAL value is still observable.
                var expectOptionsExpanded = Quickshell.env("QSG_TEST_EXPECT_OPTIONS_EXPANDED");
                if (expectOptionsExpanded === "0" || expectOptionsExpanded === "1") {
                    check("optionsExpandedInitializesFromSettings",
                        dlg.optionsExpanded, expectOptionsExpanded === "1");
                }

                var before = dlg.optionsExpanded;
                dlg.toggleOptions();
                if (pickerOff) {
                    check("toggleIsNoOpWhenPickerDisabled", dlg.optionsExpanded, before);
                    check("comboStaysHiddenWhenPickerDisabled", dlg.testComboVisible, false);
                } else {
                    check("toggleFlipsWhenPickerEnabled", dlg.optionsExpanded, !before);
                }
            }

            console.log("LOGON-PRECEDENCE-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
            Qt.quit();
        });
        t.start();
    }
}
