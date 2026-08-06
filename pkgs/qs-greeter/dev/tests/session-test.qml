import QtQuick
import Quickshell

// Session.qml, MockBackend.qml, Log.qml and scenarios/ are same-directory
// symlinks to the real greeter/ and dev/ files (see settings-load-test.qml's
// header for why a directory-crossing import does not work under `qs -p`).
// Session and MockBackend are used bare below, exactly as shell.qml and
// GreetdBackend will use Session in production -- no import alias, no copy.
//
// The brief's version of this test drove scenarios with fixed millisecond
// delays (step(200, ...), step(300, ...)). That is exactly the kind of race
// Task 5's FileView fix eliminated: it will falsely pass or fail depending
// on machine load. Every step below instead polls for the actual state
// transition it depends on and only proceeds once that transition has
// happened (or loudly fails on a generous timeout). The one place a delay is
// intrinsic to the scenario is silent-2FA, where the whole point is that
// nothing happens for 1.5s -- even there we wait for waitingForDevice to
// become true rather than asserting at a fixed instant.
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0
    property var queue: []
    // Counts every readyToLaunch that reaches the test, across every
    // scenario. Used by the timer-isolation block below to prove an
    // abandoned scenario's pending step never delivers its signal late.
    property int readyCount: 0
    property real leakBaseline: 0
    property real abandonAt: 0

    function check(name, got, want) {
        total++;
        if (got === want) pass++;
        else console.log("SESSION-TEST CASE FAIL: " + name + " got=" + got + " want=" + want);
    }

    MockBackend { id: mock }

    Connections {
        target: mock
        function onReadyToLaunch() { root.readyCount++; }
    }

    // Queue entries:
    //   ["action", fn]                                  -- run fn, then continue
    //   ["wait", label, predicateFn, timeoutMs, thenFn]  -- poll predicateFn
    //     every 20ms; once true (or timeoutMs elapses -- itself a loud
    //     failure, not a silent skip) run thenFn and continue.
    function action(fn) { queue.push(["action", fn]); }
    function wait(label, predicateFn, timeoutMs, thenFn) {
        queue.push(["wait", label, predicateFn, timeoutMs, thenFn]);
    }

    function drain() {
        if (queue.length === 0) {
            console.log("SESSION-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
            Qt.quit();
            return;
        }
        var head = queue.shift();
        if (head[0] === "action") {
            head[1]();
            root.drain();
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
                // A timeout is a real failure, not a skip -- it means the
                // awaited transition never happened within a generous budget.
                check(label + "Timeout", "timed-out-after-" + timeoutMs + "ms", "condition-met");
                thenFn();
                root.drain();
            }
        });
        t.start();
    }

    Component.onCompleted: {
        Session.backend = mock;

        // --- happy path ---
        action(function () {
            mock.loadScenario("happy");
            Session.begin("michael");
            check("stateAuthenticating", Session.state, "authenticating");
        });
        wait("happyPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            check("promptLabel", Session.promptLabel, "Password:");
            check("promptSecret", Session.promptSecret, true);
            Session.submit("hunter2");
        });
        wait("happyReady", function () { return Session.state === "ready"; }, 2000, function () {
            check("readyAfterCorrect", Session.state, "ready");
        });

        // --- wrong password: failure count, backoff, session cancelled ---
        action(function () {
            Session.cancel();
            mock.loadScenario("wrong-password");
            Session.begin("michael");
        });
        wait("wrongPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("nope");
        });
        wait("wrongFailed", function () { return Session.state === "failed"; }, 2000, function () {
            check("failedState", Session.state, "failed");
            check("failureCounted", Session.failures, 1);
            check("cancelledAfterFailure", mock.cancelCount >= 1, true);
        });

        // --- info message renders as status, not a prompt, and is never
        // responded to ---
        action(function () {
            Session.cancel();
            mock.loadScenario("touch-2fa");
            Session.begin("michael");
        });
        wait("touchPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("hunter2");
        });
        wait("touchInfoArrived", function () { return Session.statusText === "Please touch the device"; }, 2500, function () {
            check("infoIsStatus", Session.statusText, "Please touch the device");
            check("infoNotPrompt", Session.promptLabel, "Password:");
            check("infoNoRespond", mock.respondCount, 1);
        });

        // --- protocol error is distinct from an auth failure ---
        action(function () {
            Session.cancel();
            mock.loadScenario("protocol-error");
            Session.begin("michael");
        });
        wait("protocolError", function () { return Session.statusIsError === true; }, 2000, function () {
            check("protocolErrorStatus", Session.statusIsError, true);
            check("protocolErrorIdle", Session.state, "idle");
        });

        // --- silent 2FA: the heuristic fires with no message at all ---
        action(function () {
            Session.cancel();
            mock.loadScenario("silent-2fa");
            Session.begin("michael");
        });
        wait("silentPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("hunter2");
        });
        wait("silentHint", function () { return Session.waitingForDevice === true; }, 3000, function () {
            check("silentHint", Session.waitingForDevice, true);
        });

        // --- timer isolation: an abandoned scenario's pending step must
        // never fire into whatever scenario runs next. Regression test for
        // the MockBackend timer-leak bug: revert the _killTimers() calls in
        // loadScenario()/cancelSession() and this block fails, because the
        // abandoned silent-2fa readyToLaunch (scheduled ~4000ms after
        // respond) survives the cancel/reload and lands on top of
        // wrong-password. silent-2fa's own respond-gated step has a long
        // enough delay to comfortably abandon before it would fire.
        action(function () {
            Session.cancel();
            mock.loadScenario("silent-2fa");
            root.leakBaseline = root.readyCount;
            Session.begin("michael");
        });
        wait("isoPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("hunter2"); // schedules the abandoned scenario's readyToLaunch ~4000ms out
            root.abandonAt = Date.now();
        });
        action(function () {
            // Well before the 4000ms elapses: cancel kills the pending
            // timer, then a completely different scenario loads and begins.
            Session.cancel();
            mock.loadScenario("wrong-password");
            Session.begin("michael");
        });
        wait("isoNewPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            check("isoNewScenarioLoaded", Session.promptLabel, "Password:");
        });
        // The assertion here is a negative ("it must not have fired"), which
        // cannot be expressed as "wait until true" -- this and silent-2fa's
        // own wait are the only two places a real elapsed delay is
        // unavoidable. Wait out the abandoned step's original window (plus
        // margin) and confirm no extra readyToLaunch arrived during it.
        wait("isoWindowElapsed", function () { return Date.now() - root.abandonAt > 4300; }, 6000, function () {
            check("noLeakedReadyToLaunch", root.readyCount, root.leakBaseline);
        });

        drain();
    }
}
