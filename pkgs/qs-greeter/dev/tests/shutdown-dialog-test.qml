import QtQuick
import Quickshell
import "xp-kit" as XpKit
import "xp-kit/palettes" as XpPalettes
import "xp-kit/screens" as XpScreens

// Task 11: the XP "Shut Down Windows" modal (screens/ShutDownDialog.qml)
// and its wiring into Skin.qml (`shutDownVisible` plus the dim/disable
// treatment of the screen beneath it). Two parts:
//
//   1. ShutDownDialog.qml driven standalone, the same technique
//      widgets-gallery.qml uses for the widget kit: the combo's three
//      rows in order, the description line tracking the selection
//      (exact strings), OK's mapped requestPower(action) per row,
//      Cancel/Escape's cancelled() with NO requestPower, Return's mapped
//      action, and Help's balloon.
//   2. The REAL chain through Skin.qml, reached via xp-kit/Skin.qml (the
//      same mirror technique skin-smoke-test.qml uses to reach
//      Skin.qml/SkinFatal.qml): LogonDialog's own "Shut Down..." button
//      -- its shutDownRequested() signal, invoked directly the way a real
//      click would fire it (no synthetic-mouse-click path under the
//      offscreen QPA platform, same as every other suite in this
//      directory) -- actually opens the modal, dims and disables
//      LogonDialog while it is up, and OK's action reaches Skin.qml's own
//      top-level requestPower(action) signal: the exact one shell.qml
//      connects to shellRoot.power() in production. SkinFatal's own
//      "Shut Down..." button is proven to reach the same seam via a
//      SECOND, separate Skin instance (session/sessions left null, the
//      same "greetd not available yet" state skin-smoke-test.qml uses to
//      route to SkinFatal instead of LogonDialog).
//
// This process NEVER constructs shell.qml and there is no Process/
// Quickshell.Io anywhere in its import graph -- requestPower is observed
// purely as a JS signal connection (skin.requestPower.connect(...), the
// same technique widgets-gallery.qml uses for XpMessageBox.accepted), so
// there is no path from this file to a real systemctl call even by
// accident: nothing here can spawn a process at all, let alone one with
// an interpolated argv.
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0

    function check(name, got, want) {
        total++;
        if (JSON.stringify(got) === JSON.stringify(want)) pass++;
        else console.log("SHUTDOWN-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
    }
    function ok(name, cond) {
        total++;
        if (cond) pass++;
        else console.log("SHUTDOWN-TEST CASE FAIL: " + name);
    }

    MockBackend { id: mock }
    // Same QSG_TEST_PALETTE seam as logon-dialog-test.qml (see its own
    // comment): lets the runner drive Part 1's standalone ShutDownDialog
    // fixture under both registered palettes. Parts 2/2b go through the
    // REAL Skin.qml, which resolves its own theme from Settings.palette
    // (see Skin.qml's `theme` property) -- those are covered separately,
    // by pointing QSG_DEFAULTS at a skinSettings.xp.palette of "gruvbox".
    XpKit.Theme { id: themeLuna }
    XpPalettes.Gruvbox { id: themeGruvbox }
    readonly property var theme:
        Quickshell.env("QSG_TEST_PALETTE") === "gruvbox" ? themeGruvbox : themeLuna

    // --- Part 1 fixture: ShutDownDialog on its own. Nested one Item deep
    // under ShellRoot, not a direct child of it: a direct ShellRoot child's
    // own `visible` does not behave like an ordinary Item's under
    // QT_QPA_PLATFORM=offscreen with no PanelWindow backend (confirmed by
    // isolated repro -- toggling a direct child's `visible` false then
    // true back-to-back silently leaves it false, presumably because
    // Quickshell treats a direct ShellRoot child as an implicit
    // window-like root tied to a backend that does not exist here; see
    // "No PanelWindow backend loaded" in Task 10's own store-output
    // check). One plain wrapper Item sidesteps it entirely, confirmed by
    // the same repro. This only matters for THIS file's own
    // visible-cycle reopen check below -- production never has this
    // problem (ShutDownDialog.qml is nested inside Skin.qml's own Item
    // tree, never a bare ShellRoot child, and a real PanelWindow backend
    // exists there anyway). ---
    Item {
        id: dlgHost
        XpScreens.ShutDownDialog {
            id: dlg
            theme: root.theme
        }
    }

    // --- Part 2 fixture: the real Skin.qml, routed to LogonDialog
    // (session/sessions/settings wired the way shell.qml wires them, so
    // this instance's theme really does come from QSG_DEFAULTS' palette
    // as the comment above claims, not from Skin.qml's own "no settings
    // yet" fallback). ---
    XpKit.Skin {
        id: skin
        session: Session
        sessions: Sessions
        settings: XpKit.Settings
    }

    // --- Part 2b fixture: a SECOND, independent Skin.qml instance,
    // session/sessions left null on purpose -- routes to SkinFatal
    // instead (same technique skin-smoke-test.qml uses), so SkinFatal's
    // own shutDownRequested() seam gets proven against a real instance
    // too, without disturbing `skin` above (which must stay routed to
    // LogonDialog for the rest of this file's checks). settings is wired
    // for the same theme-source parity as `skin` above even though
    // SkinFatal never reads it directly. ---
    XpKit.Skin {
        id: fatalSkin
        settings: XpKit.Settings
    }

    Component.onCompleted: {
        Session.backend = mock;

        var t = Qt.createQmlObject('import QtQuick; Timer { interval: 20; repeat: true }', root);
        var start = Date.now();
        t.triggered.connect(function () {
            var settled = Sessions.ready === true && XpScreens.Settings.ready === true;
            if (!settled && Date.now() - start <= 2000) return;
            t.stop(); t.destroy();
            root._runChecks();
        });
        t.start();
    }

    function _runChecks() {
        // === Part 1: ShutDownDialog standalone ===

        check("comboOffersExactlyThreeActionsInOrder", dlg.testActionLabels,
            ["Stand By", "Turn Off", "Restart"]);

        dlg.testSelectIndex(0);
        check("descriptionStandBy", dlg.testDescriptionText,
            "Maintains your session, keeping the computer running on low power with data still in memory.");
        dlg.testSelectIndex(1);
        check("descriptionTurnOff", dlg.testDescriptionText,
            "Ends your session and turns off the computer.");
        dlg.testSelectIndex(2);
        check("descriptionRestart", dlg.testDescriptionText,
            "Ends your session and restarts the computer.");

        // OK emits requestPower with the correctly-mapped action, for
        // each of the three selections.
        [[0, "suspend"], [1, "poweroff"], [2, "reboot"]].forEach(function (pair) {
            var idx = pair[0], want = pair[1];
            var got = null;
            var conn = function (action) { got = action; };
            dlg.requestPower.connect(conn);
            dlg.testSelectIndex(idx);
            dlg._ok();
            dlg.requestPower.disconnect(conn);
            check("okEmitsRequestPowerForIndex" + idx, got, want);
        });

        // Cancel: fires cancelled(), never requestPower.
        (function () {
            var cancelled = false, powerFired = false;
            var cConn = function () { cancelled = true; };
            var pConn = function () { powerFired = true; };
            dlg.cancelled.connect(cConn);
            dlg.requestPower.connect(pConn);
            dlg._cancel();
            dlg.cancelled.disconnect(cConn);
            dlg.requestPower.disconnect(pConn);
            ok("cancelFiresCancelled", cancelled === true);
            ok("cancelDoesNotFireRequestPower", powerFired === false);
        })();

        // Escape via the real Keys signal (not just _cancel() directly --
        // same technique Task 10's fix round used for LogonDialog.qml:
        // dlg.Keys.escapePressed(null) fires the real onEscapePressed
        // handler without going through Qt's actual input dispatch).
        // Fires cancelled(), never requestPower.
        (function () {
            var cancelled = false, powerFired = false;
            var cConn = function () { cancelled = true; };
            var pConn = function () { powerFired = true; };
            dlg.cancelled.connect(cConn);
            dlg.requestPower.connect(pConn);
            dlg.Keys.escapePressed(null);
            dlg.cancelled.disconnect(cConn);
            dlg.requestPower.disconnect(pConn);
            ok("escapeSignalFiresCancelled", cancelled === true);
            ok("escapeSignalDoesNotFireRequestPower", powerFired === false);
        })();

        // Return via the real Keys signal: OK's mapped action, same as a
        // direct _ok() call.
        (function () {
            var got = null;
            var conn = function (action) { got = action; };
            dlg.requestPower.connect(conn);
            dlg.testSelectIndex(1);
            dlg.Keys.returnPressed(null);
            dlg.requestPower.disconnect(conn);
            check("returnSignalEmitsMappedAction", got, "poweroff");
        })();

        // Help opens the balloon rather than doing nothing.
        ok("helpBalloonStartsClosed", dlg.testHelpBalloonVisible === false);
        dlg._help();
        ok("helpOpensBalloon", dlg.testHelpBalloonVisible === true);

        // Reopening (a hide/show cycle) resets to Stand By and closes the
        // help balloon -- dlg was constructed visible (Item's own
        // default), so drive an explicit cycle to exercise that reset.
        dlg.testSelectIndex(2);
        dlg.visible = false;
        dlg.visible = true;
        check("reopenResetsToStandBy", dlg.testCurrentIndex, 0);
        ok("reopenClosesHelpBalloon", dlg.testHelpBalloonVisible === false);

        // === Part 2: the real chain through Skin.qml ===

        ok("skinRoutesToLogonDialog", skin._fatal === false);
        ok("modalInitiallyClosed", skin.shutDownVisible === false);
        ok("shutDownDialogInitiallyHidden", skin.testShutDownDialog.visible === false);
        ok("logonDialogInitiallyEnabled", skin.testLogonDialog.enabled === true);
        ok("logonDialogInitiallyFullOpacity", skin.testLogonDialog.opacity === 1.0);

        // The real seam: LogonDialog's "Shut Down..." button fires this
        // exact signal (see LogonDialog.qml's `buttons` array).
        skin.testLogonDialog.shutDownRequested();
        ok("shutDownRequestedOpensTheModal", skin.shutDownVisible === true);
        ok("shutDownDialogNowVisible", skin.testShutDownDialog.visible === true);
        ok("logonDialogNowDisabled", skin.testLogonDialog.enabled === false);
        ok("logonDialogNowDimmed", skin.testLogonDialog.opacity < 1.0);

        // OK's action reaches Skin.qml's OWN top-level requestPower --
        // proving the forward from ShutDownDialog through Skin.qml, not
        // just ShutDownDialog's own local signal (Part 1 already proved
        // that half in isolation).
        (function () {
            var got = null;
            var conn = function (action) { got = action; };
            skin.requestPower.connect(conn);
            skin.testShutDownDialog.testSelectIndex(2);
            skin.testShutDownDialog._ok();
            skin.requestPower.disconnect(conn);
            check("skinRequestPowerReceivesMappedAction", got, "reboot");
        })();
        ok("okClosesTheModal", skin.shutDownVisible === false);
        ok("logonDialogReenabledAfterOk", skin.testLogonDialog.enabled === true);
        ok("logonDialogFullOpacityAfterOk", skin.testLogonDialog.opacity === 1.0);

        // Reopen, then Cancel: closes without Skin.qml's requestPower
        // ever firing -- the "Cancel/Escape close it without emitting
        // anything" requirement, proven at the Skin.qml level (not just
        // ShutDownDialog's own local signal, which Part 1 already
        // covers).
        skin.testLogonDialog.shutDownRequested();
        ok("reopenedForCancelCheck", skin.shutDownVisible === true);
        // Final micro-fix, Item 2: Skin.qml disables (not hides) LogonDialog
        // while the modal is up, so `visible` never changes and neither of
        // LogonDialog's own visible-gated focus claims fires for this
        // transition -- captured before the cancel below so the assertion
        // that follows proves a NEW claim happened, not just that one
        // happened at some earlier point (e.g. at construction).
        var forceFocusCallsBeforeCancel = skin.testLogonDialog.testUserFieldForceFocusCalls;
        (function () {
            var powerFired = false;
            var conn = function () { powerFired = true; };
            skin.requestPower.connect(conn);
            skin.testShutDownDialog._cancel();
            skin.requestPower.disconnect(conn);
            ok("cancelClosesWithoutSkinRequestPower", powerFired === false);
        })();
        ok("cancelClosesTheModal", skin.shutDownVisible === false);
        ok("logonDialogReenabledAfterCancel", skin.testLogonDialog.enabled === true);
        // The core assertion this item is about: re-enabling the dialog
        // after Cancel must re-claim focus on the user field, the same
        // field the dialog claims on first becoming visible. activeFocus
        // itself is not observable under offscreen QPA (see XpTextField.
        // qml's own comment); this proves the CODE PATH that would set it
        // actually ran again, which is what regressed (onEnabledChanged
        // never firing that call at all is the exact bug this item fixes).
        ok("focusReclaimedAfterShutDownCancel",
            skin.testLogonDialog.testUserFieldForceFocusCalls > forceFocusCallsBeforeCancel);

        // === Part 2b: SkinFatal's own seam, on the independent instance ===
        ok("fatalSkinRoutesToSkinFatal", fatalSkin._fatal === true);
        ok("fatalModalInitiallyClosed", fatalSkin.shutDownVisible === false);
        fatalSkin.testSkinFatal.shutDownRequested();
        ok("skinFatalShutDownRequestedOpensTheModal", fatalSkin.shutDownVisible === true);
        ok("fatalSkinFatalNowDisabled", fatalSkin.testSkinFatal.enabled === false);

        // `skin` (Part 2's instance) must be entirely unaffected by
        // fatalSkin's own modal -- these are two independent Item trees,
        // not a shared one; this is the same "two directories, two
        // instances" class of mistake this plan has hit before (see
        // LogonDialog.qml's own header comment on Settings), checked here
        // for shutDownVisible specifically because it is new state this
        // task adds.
        ok("skinUnaffectedByFatalSkinsModal", skin.shutDownVisible === false);

        console.log("SHUTDOWN-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }
}
