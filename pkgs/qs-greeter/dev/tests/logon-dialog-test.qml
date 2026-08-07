import QtQuick
import Quickshell
import "xp-kit" as XpKit
import "xp-kit/palettes" as XpPalettes
import "xp-kit/screens" as XpScreens

// Deep behavioral test for the XP logon dialog (Task 10), same queue/poll
// style as session-test.qml (see its header for why: a fixed millisecond
// delay is exactly the kind of race Task 5's FileView fix eliminated, so
// every step polls for the transition it depends on rather than guessing a
// delay). Session, Sessions, Settings, GreeterState, CapsLock, MockBackend
// and scenarios/ are all same-directory symlinks to the real greeter/dev
// singletons and fixtures (see this directory's other *-test.qml files for
// the same technique) -- this drives the REAL LogonDialog.qml, reached
// through the xp-kit/ mirror (the same technique widgets-gallery.qml uses
// to reach the widget kit), against the REAL Session state machine. Nothing
// here is a stand-in for either.
//
// QSG_DEFAULTS/QSG_SESSIONS/QSG_STATE_FILE point at fixtures the runner
// (logon-dialog-test.sh) builds in a tmp dir: three sessions with a shell
// last, and sessions.picker: true so the Options row is reachable.
// logon-dialog-precedence-test.qml covers the picker-off gate and the
// Settings-default-vs-GreeterState.lastSession precedence, which both need
// DIFFERENT global Settings/GreeterState fixtures than this file uses --
// Settings and GreeterState are singletons, so only one fixture combination
// can be live per process. This file also reaches CapsLock/GreeterState
// through the XpScreens-qualified import rather than bare where it needs
// to observe the SAME instance LogonDialog.qml uses internally -- see the
// comment where those first appear below for why a bare reference from
// this file's own directory is not that instance.
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0
    property var queue: []

    function check(name, got, want) {
        total++;
        if (got === want) pass++;
        else console.log("LOGON-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
    }
    function ok(name, cond) {
        total++;
        if (cond) pass++;
        else console.log("LOGON-TEST CASE FAIL: " + name);
    }

    MockBackend { id: mock }
    // Palette selection for this run: QSG_TEST_PALETTE lets the .sh runner
    // drive this entire ~50-assertion behavioral suite under BOTH
    // registered palettes (Task 12's requirement that the existing
    // suites still pass under Gruvbox, not just Luna) without duplicating
    // the suite into a second file. This suite drives LogonDialog.qml
    // standalone -- theme is handed to it directly, exactly as before;
    // it never goes through Settings/Skin.qml's own palette resolution
    // (that resolution path is covered separately, at the Skin.qml level,
    // by skin-smoke-test.qml and shutdown-dialog-test.qml's Part 2).
    XpKit.Theme { id: themeLuna }
    XpPalettes.Gruvbox { id: themeGruvbox }
    readonly property var theme:
        Quickshell.env("QSG_TEST_PALETTE") === "gruvbox" ? themeGruvbox : themeLuna

    XpScreens.LogonDialog {
        id: dlg
        theme: root.theme
        session: Session
        sessions: Sessions
    }

    property real fixedUserRow: 0
    property real fixedSecretRow: 0

    function action(fn) { queue.push(["action", fn]); }
    function wait(label, predicateFn, timeoutMs, thenFn) {
        queue.push(["wait", label, predicateFn, timeoutMs, thenFn]);
    }
    // A pure delay, asserting nothing -- distinct from wait() above, whose
    // timeout path always counts as a failed assertion if the predicate
    // never turns true. Exists for GreeterState.qml's FileView.writeAdapter():
    // each write runs on a background QThreadPool worker (confirmed by
    // reading Quickshell's own fileview.cpp), with no queueing between
    // successive setData() calls on the same FileView -- two save() calls
    // issued close together race two independent writer threads, and
    // whichever happens to finish LAST wins regardless of which was issued
    // last, which is backwards under load. A real login never calls save()
    // twice within milliseconds of another (human typing speed, not two
    // MockBackend-driven instant logins back to back), so this is a
    // synthetic-test-only hazard, not a production one -- reproduced and
    // root-caused by hand (comboIdx/entry/session.user were already
    // correct at the point of the SECOND _launchSelected() call; the
    // GreeterState fields read back moments later reverted to the FIRST
    // call's values regardless), not worked around blind.
    function pause(ms) { queue.push(["pause", ms]); }
    function drain() {
        if (queue.length === 0) {
            console.log("LOGON-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
            Qt.quit();
            return;
        }
        var head = queue.shift();
        if (head[0] === "action") {
            head[1]();
            root.drain();
        } else if (head[0] === "pause") {
            var pt = Qt.createQmlObject('import QtQuick; Timer { repeat: false }', root);
            pt.interval = head[1];
            pt.triggered.connect(function () { pt.destroy(); root.drain(); });
            pt.start();
        } else {
            _pollUntil(head[1], head[2], head[3], head[4]);
        }
    }
    function _pollUntil(label, predicateFn, timeoutMs, thenFn) {
        var start = Date.now();
        var t = Qt.createQmlObject('import QtQuick; Timer { interval: 20; repeat: true }', root);
        t.triggered.connect(function () {
            if (predicateFn()) {
                t.stop(); t.destroy();
                thenFn();
                root.drain();
            } else if (Date.now() - start > timeoutMs) {
                t.stop(); t.destroy();
                check(label + "Timeout", "timed-out-after-" + timeoutMs + "ms", "condition-met");
                thenFn();
                root.drain();
            }
        });
        t.start();
    }

    Component.onCompleted: {
        Session.backend = mock;

        // --- baseline: banner/field rows have a real, fixed height before
        // anything happens; every later check re-confirms it hasn't moved.
        // Also the ONLY place this suite checks the FALLBACK label text
        // (idle, no live prompt) -- every other "Password:" check below
        // happens mid-authentication, where the value comes from
        // session.promptLabel (the scenario's own text), not this
        // fallback branch, so none of them would catch a mutation to the
        // fallback string itself. ---
        action(function () {
            root.fixedUserRow = dlg.testUserRowHeight;
            root.fixedSecretRow = dlg.testSecretRowHeight;
            ok("userRowHasRealHeight", root.fixedUserRow > 0);
            ok("secretRowHasRealHeight", root.fixedSecretRow > 0);
            check("fallbackLabelIsPasswordWhenIdle", dlg.testSecretFieldLabel, "Password:");
        });

        // --- the active field is chrome: it tracks whatever PAM last
        // asked for, not a hardcoded "Password:". Proven with a prompt
        // that is NOT "Password:", so a hardcoded label would fail this.
        // Session._state is poked directly (not begin()) to isolate the
        // label/echo BINDING from the rest of the state machine, which
        // the scenario-driven blocks below already exercise. ---
        action(function () {
            Session.cancel();
            Session._state = "authenticating";
            Session.promptLabel = "Enter PIN:";
            Session.promptSecret = false;
            check("labelTracksArbitraryPamPrompt", dlg.testSecretFieldLabel, "Enter PIN:");
            check("echoFollowsPromptSecretFalse", dlg.testSecretFieldEchoMode, TextInput.Normal);
            Session.promptSecret = true;
            check("echoFollowsPromptSecretTrue", dlg.testSecretFieldEchoMode, TextInput.Password);
            check("rowsUnchangedByArbitraryPrompt", dlg.testSecretRowHeight, root.fixedSecretRow);
            Session._state = "idle";
            Session.promptLabel = "";
        });

        // --- happy path end to end, through the real scenario/MockBackend
        // machinery this time: label reads back "Password:" because THAT
        // is what the scenario actually prompted for, not because it is
        // hardcoded (the block above already proved it is not) ---
        action(function () {
            mock.loadScenario("happy");
            Session.begin("michael");
            check("userFieldDisabledWhileAuthenticating", dlg.testUserFieldEnabled, false);
        });
        wait("happyPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            check("labelFollowsRealPrompt", dlg.testSecretFieldLabel, "Password:");
            check("echoFollowsRealPromptSecret", dlg.testSecretFieldEchoMode, TextInput.Password);
            check("rowsUnchangedDuringAuth", dlg.testUserRowHeight, root.fixedUserRow);
            Session.submit("hunter2");
        });
        // The dialog's own onStateChanged handler launches synchronously
        // the instant Session reaches "ready" (see LogonDialog.qml's
        // _launchSelected()), so "ready" is never independently observable
        // here -- by the time this poll's next tick runs, MockBackend's
        // inert launch() has already fired and Session is "launched".
        wait("happyLaunched", function () { return Session.state === "launched"; }, 2000, function () {
            check("reachedLaunched", Session.state, "launched");
            check("rowsUnchangedAfterLaunch", dlg.testUserRowHeight, root.fixedUserRow);
        });

        // --- wrong password: a failure surfaces the message box with the
        // exact canned text, clears the secret field, and does not move
        // the fixed rows ---
        action(function () {
            Session.cancel();
            mock.loadScenario("wrong-password");
            Session.begin("michael");
        });
        wait("wrongPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("nope");
        });
        wait("wrongFailed", function () { return Session.state === "failed"; }, 2000, function () {
            check("messageBoxShownOnFailure", dlg.testMsgBoxVisible, true);
            check("messageBoxCannedText", dlg.testMsgBoxText,
                "The system could not log you on. Make sure your User name and password are correct.");
            check("secretFieldClearedOnFailure", dlg.testSecretFieldText, "");
            check("rowsUnchangedOnFailure", dlg.testUserRowHeight, root.fixedUserRow);
        });

        // --- F4: a prompt sequence secret-then-visible must never leave
        // the PRIOR prompt's text sitting in the field once the new
        // prompt's echo mode has taken effect. secret-then-visible.json
        // asks an echo-off "Password:" first, then (after that response)
        // an echo-on "Confirm code:" -- exactly the shape the finding
        // describes: if the field is not cleared until session.state
        // changes or _cancel() runs (as it was before this fix), the
        // password typed for step one would render in CLEARTEXT the
        // instant step two's echo-on mode applies to it. session.
        // promptArriving() fires (and this file's Connections handler
        // clears secretField.text) strictly before promptLabel/
        // promptSecret change, so by the time this poll observes the new
        // label, the field must already read empty -- this assertion is
        // exactly what would go red if that ordering, or the clear
        // itself, regressed. ---
        action(function () {
            Session.cancel();
            mock.loadScenario("secret-then-visible");
            Session.begin("f4testuser");
        });
        wait("secretThenVisiblePrompt1", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            dlg.testSetSecretText("hunter2");
            check("secretPromptEchoIsOff", dlg.testSecretFieldEchoMode, TextInput.Password);
            Session.submit("hunter2");
        });
        wait("secretThenVisiblePrompt2", function () { return Session.promptLabel === "Confirm code:"; }, 2000, function () {
            check("priorSecretNeverLeaksIntoVisiblePrompt", dlg.testSecretFieldText, "");
            check("secondPromptEchoIsOn", dlg.testSecretFieldEchoMode, TextInput.Normal);
        });
        action(function () { Session.cancel(); });

        // --- info message (touch-2fa): renders as status text, does NOT
        // create a third input, and is never responded to a second time ---
        action(function () {
            Session.cancel();
            mock.loadScenario("touch-2fa");
            Session.begin("michael");
        });
        wait("touchPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("hunter2");
        });
        wait("touchInfoArrived", function () { return Session.statusText === "Please touch the device"; }, 2500, function () {
            check("infoRendersAsStatusLine", dlg.statusLineText, "Please touch the device");
            check("infoDidNotChangeActiveLabel", dlg.testSecretFieldLabel, "Password:");
            check("infoDidNotTriggerASecondRespond", mock.respondCount, 1);
            check("rowsUnchangedByInfoMessage", dlg.testUserRowHeight, root.fixedUserRow);
        });
        action(function () {
            var before = mock.respondCount;
            dlg._ok(); // OK during the info window must not double-respond
            check("okDuringInfoWindowIsANoOp", mock.respondCount, before);
        });
        action(function () { Session.cancel(); });

        // --- Cancel: _cancel() clears the secret field, leaves the
        // username field alone (cancel should not punish the user for a
        // mistyped password), reaches Session.cancel() (proven via
        // mock.cancelCount actually incrementing, not just that the
        // method was called), returns state to idle, and does not wedge
        // the dialog -- a fresh OK afterward must be able to start a new
        // attempt and reach a prompt again. Invoked as dlg._cancel(), the
        // exact function Keys.onEscapePressed delegates to (see the
        // Enter/Escape block below for what that adds on top of this). ---
        action(function () {
            Session.cancel();
            XpScreens.GreeterState.lastUser = "canceltestuser"; // seeds userField.text via its own binding
            mock.loadScenario("happy");
            Session.begin("canceltestuser");
        });
        wait("cancelPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            dlg.testSetSecretText("typed-but-not-submitted");
            check("secretPopulatedBeforeCancel", dlg.testSecretFieldText, "typed-but-not-submitted");
            check("userFieldPopulatedBeforeCancel", dlg.testUserFieldText, "canceltestuser");
        });
        action(function () {
            var cancelsBefore = mock.cancelCount;
            dlg._cancel();
            check("secretClearedByCancel", dlg.testSecretFieldText, "");
            check("usernameNotClearedByCancel", dlg.testUserFieldText, "canceltestuser");
            ok("cancelReachedTheSession", mock.cancelCount > cancelsBefore);
            check("stateReturnsToIdleAfterCancel", Session.state, "idle");
        });
        action(function () {
            dlg._ok(); // cancel must not wedge the dialog: a fresh OK starts a new attempt
        });
        wait("freshPromptAfterCancel", function () { return Session.promptLabel === "Password:" && Session.state === "authenticating"; }, 2000, function () {
            check("cancelDoesNotWedgeTheDialog", Session.state, "authenticating");
        });
        action(function () { Session.cancel(); });

        // --- Enter/Escape: Keys.onReturnPressed/Keys.onEscapePressed are
        // one-line delegations to _ok()/_cancel() (both already covered
        // above); this additionally proves the ATTACHED PROPERTY SIGNAL
        // itself is wired to them, by invoking the signal directly
        // (Keys.escapePressed/returnPressed are ordinary QML signals,
        // callable like functions) rather than only re-testing _ok()/
        // _cancel() under a different name. This is NOT a synthetic key
        // event -- there is no synthetic-keyboard path under
        // QT_QPA_PLATFORM=offscreen (the same limitation XpComboBox's own
        // tests document, see widgets-gallery.qml) -- so it proves the
        // wiring from the signal to the function, not that a real OS
        // keypress reaches this Item through an actual compositor's focus
        // chain. Whether Tab/click focus actually lands on this dialog in
        // a live session is NOT covered here and needs the interactive
        // pass. `null` is passed as the KeyEvent argument because neither
        // handler reads it (both call a zero-argument function), and it
        // is the one value that does not also log a spurious "Could not
        // convert argument" warning (confirmed empirically: a plain {}
        // does log one; calling with no argument at all throws
        // "Insufficient arguments" instead of emitting anything). ---
        action(function () {
            Session.cancel();
            mock.loadScenario("happy");
            Session.begin("keytestuser");
        });
        wait("keyEscapePrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            var cancelsBefore = mock.cancelCount;
            dlg.Keys.escapePressed(null);
            check("escapeSignalReachesIdle", Session.state, "idle");
            ok("escapeSignalReachedTheSession", mock.cancelCount > cancelsBefore);
        });
        action(function () {
            mock.loadScenario("happy");
            Session.begin("keytestuser2");
        });
        wait("keyReturnPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            dlg.testSetSecretText("hunter2");
            dlg.Keys.returnPressed(null);
        });
        wait("keyReturnLaunched", function () { return Session.state === "launched"; }, 2000, function () {
            check("returnSignalReachesOkAndLaunches", Session.state, "launched");
        });
        action(function () { Session.cancel(); });

        // --- status line priority: blocked countdown > waiting-for-device
        // hint > plain Session.statusText, in that exact order ---
        action(function () {
            Session.blockedUntil = 0;
            Session.waitingForDevice = false;
            Session.statusText = "";
        });
        action(function () {
            Session.waitingForDevice = true;
        });
        wait("waitingHintShown", function () { return dlg.statusLineText === "Waiting for your security key..."; }, 500, function () {
            check("waitingHintExactText", dlg.statusLineText, "Waiting for your security key...");
        });
        action(function () {
            Session.blockedUntil = Math.floor(Date.now() / 1000) + 2;
        });
        wait("blockRecognized", function () { return dlg.blocked === true; }, 1000, function () {
            ok("blockedBeatsWaitingHint", dlg.statusLineText.indexOf("Too many attempts") === 0);
            check("okDisabledWhileBlocked", dlg.testOkEnabled, false);
        });
        wait("blockClears", function () { return dlg.blocked === false; }, 5000, function () {
            check("okReenabledAfterBlockExpires", dlg.testOkEnabled, true);
            check("fallsBackToWaitingHintOnceUnblocked", dlg.statusLineText, "Waiting for your security key...");
        });
        action(function () {
            Session.waitingForDevice = false;
            Session.statusText = "plain backend status";
            check("plainStatusTextWhenNothingElsePending", dlg.statusLineText, "plain backend status");
            Session.statusText = "";
        });

        // --- Caps Lock balloon ---
        // Poked via XpScreens.CapsLock (not the bare CapsLock this file
        // also has its own local symlink for), because Quickshell's
        // per-directory singleton registration mints an INDEPENDENT
        // instance per directory even when the symlinks resolve to the
        // same real file underneath -- confirmed empirically (a two-
        // directory repro: writing a shared singleton's property from one
        // directory's own bare reference left the other directory's own
        // bare reference completely unaffected). Bare `CapsLock` from
        // this file would poke THIS file's own instance, not the one
        // LogonDialog.qml (loaded through the xp-kit/screens/ mirror)
        // actually reads from; `XpScreens.CapsLock` reaches into that
        // same imported module and gets the identical instance
        // LogonDialog.qml itself sees. session/sessions sidestep this
        // entirely because they are passed to `dlg` as PROPS (an actual
        // object reference, not a fresh per-directory lookup) -- which is
        // exactly why the contract injects those two instead of letting
        // the skin import Session/Sessions directly.
        action(function () {
            check("balloonHiddenWithoutCapsLock", dlg.testCapsBalloonVisible, false);
            XpScreens.CapsLock.on = true;
            check("balloonShownWithCapsLock", dlg.testCapsBalloonVisible, true);
            XpScreens.CapsLock.on = false;
            check("balloonHidesAgain", dlg.testCapsBalloonVisible, false);
        });

        // --- session combo: lists Sessions entries in order (shells last,
        // per wrapper/sessions-parse.sh), preselects the first entry when
        // no Settings default or GreeterState.lastSession applies, and
        // Options only reveals it because this fixture's sessions.picker
        // is true (the false case is logon-dialog-precedence-test.qml,
        // which needs its own Settings fixture). Settings.ready is read
        // via XpScreens.Settings for the same cross-directory-instance
        // reason as CapsLock above; Sessions.ready is read via the bare
        // Sessions singleton because THAT one is fine -- it is the exact
        // object passed into `dlg.sessions` as a prop above. ---
        wait("sessionsSettled", function () { return Sessions.ready === true && XpScreens.Settings.ready === true; }, 2000, function () {
            check("comboListsEverySession", dlg.testComboModel.length, 3);
            check("comboOrderMatchesSessionsList", dlg.testComboModel[0], "Hyprland (uwsm-managed)");
            check("comboShellsLast", dlg.testComboModel[dlg.testComboModel.length - 1], "zsh (console)");
            check("preselectsFirstEntryAbsentAnyDefault", dlg.testComboCurrentName, "Hyprland (uwsm-managed)");
            check("optionsInitiallyCollapsed", dlg.optionsExpanded, false);
            check("comboHiddenInitially", dlg.testComboVisible, false);
            dlg.toggleOptions();
            check("optionsExpandsWhenPickerEnabled", dlg.optionsExpanded, true);
            check("comboVisibleAfterToggle", dlg.testComboVisible, true);
        });

        // --- explicit combo selection beats every default, and reaching
        // "ready" launches exactly that entry (GreeterState is written
        // first). GreeterState read via XpScreens for the same
        // cross-directory-instance reason as CapsLock above. ---
        action(function () {
            Session.cancel();
            dlg.testSelectSessionByName("Sway (uwsm-managed)");
            check("explicitSelectionReflectedImmediately", dlg.testComboCurrentName, "Sway (uwsm-managed)");
            mock.loadScenario("happy");
            Session.begin("secondlogin");
        });
        wait("selectPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("hunter2");
        });
        wait("selectLaunched", function () { return Session.state === "launched"; }, 2000, function () {
            check("explicitSelectionWinsAtLaunch", XpScreens.GreeterState.lastSession, "Sway (uwsm-managed)");
            check("lastUserWrittenBeforeLaunch", XpScreens.GreeterState.lastUser, "secondlogin");
        });
        // See pause()'s own comment: gives this block's GreeterState.save()
        // background writer thread room to finish before the next block
        // issues another one, so the two cannot race.
        pause(500);

        // --- F5: rememberLastUser = false must skip BOTH the prefill and
        // the write-on-launch, not just one half -- a config with only one
        // of the two fixed looks like it works (the field is empty at
        // boot) while still silently leaking the username to disk on every
        // login. Settings.config is mutated directly here (through
        // XpScreens.Settings, the SAME per-directory instance
        // LogonDialog.qml itself reads -- see this file's own header note
        // on why that qualifier, not the bare singleton, is required)
        // rather than through a whole new fixture file: it is a plain
        // reassignment of an already-settled config object and needs no
        // FileView settle machinery of its own.
        //
        // Drives straight to "ready" rather than running a full
        // begin()/submit() scenario through MockBackend: the launch path
        // itself is not what this check is about. Does NOT also call
        // dlg._launchSelected() directly -- reaching "ready" here already
        // fires LogonDialog's own onStateChanged, which Qt.callLater-
        // defers straight into that SAME private helper (see that
        // handler's own comment for why the deferral exists), so calling
        // it a second time on top of that would queue two writes instead
        // of one. One trigger, one call: driven through the real state
        // transition and waited for below. ---
        action(function () {
            Session.cancel();
            var cfg = JSON.parse(JSON.stringify(XpScreens.Settings.config));
            cfg.rememberLastUser = false;
            XpScreens.GreeterState.lastUser = "sentinel-should-not-change";
            XpScreens.Settings.config = cfg;
            check("prefillSkippedWhenRememberFalse", dlg.testUserFieldText, "");
            // Deterministic, not whatever a previous block's combo click
            // left selected: dlg._comboUserSet latches once any earlier
            // block picks a session, and this suite's dlg instance is
            // shared across every block in this file.
            dlg.testSelectSessionByName("Hyprland (uwsm-managed)");
            Session.user = "rememberfalseuser";
            Session._state = "ready";
        });
        wait("rememberFalseLaunched", function () { return Session.state === "launched"; }, 1000, function () {
            check("lastSessionStillWrittenWhenRememberFalse", XpScreens.GreeterState.lastSession, "Hyprland (uwsm-managed)");
            check("lastUserWriteSkippedWhenRememberFalse", XpScreens.GreeterState.lastUser, "sentinel-should-not-change");
            // Restores rememberLastUser so this mutation does not leak into
            // whatever might run after this block in a future edit.
            var restored = JSON.parse(JSON.stringify(XpScreens.Settings.config));
            restored.rememberLastUser = true;
            XpScreens.Settings.config = restored;
            Session.cancel();
        });

        drain();
    }
}
