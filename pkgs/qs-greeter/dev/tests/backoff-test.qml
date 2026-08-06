import QtQuick
import Quickshell

// Exercises all three auth.backoff modes (disabled / global / per-user)
// through the same QSG_BACKOFF_ENABLE / QSG_BACKOFF_PERUSER env seam Session
// reads in production. The runner invokes this file three times, once per
// env combination; which block below runs is selected by what Session
// itself parsed from the environment, so the test cannot drift from what
// the env seam and the mock backend actually produced.
//
// wrong-password.json always fails with "Authentication failure" ~100ms
// after respond(); reused here to generate real auth failures.
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0
    property var queue: []

    function check(name, got, want) {
        total++;
        if (got === want) pass++;
        else console.log("BACKOFF-TEST CASE FAIL: " + name + " got=" + got + " want=" + want);
    }

    MockBackend { id: mock }

    function action(fn) { queue.push(["action", fn]); }
    function wait(label, predicateFn, timeoutMs, thenFn) {
        queue.push(["wait", label, predicateFn, timeoutMs, thenFn]);
    }
    function drain() {
        if (queue.length === 0) {
            var mode = !Session.backoffEnabled ? "DISABLED"
                : (Session.backoffPerUser ? "PERUSER" : "GLOBAL");
            console.log("BACKOFF-TEST " + mode + " " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
            Qt.quit();
            return;
        }
        var head = queue.shift();
        if (head[0] === "action") { head[1](); root.drain(); }
        else _pollUntil(head[1], head[2], head[3], head[4]);
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

    // One failed login attempt against `user`, driven through the real
    // begin()/submit() path. Only safe to use when the caller knows `user`
    // is not currently blocked -- if begin() gets refused, promptLabel
    // never arrives and the wait below times out, which is itself a loud
    // (if slightly indirect) failure rather than a hang.
    function fail(user, thenFn) {
        action(function () {
            Session.cancel();
            mock.loadScenario("wrong-password");
            Session.begin(user);
        });
        wait("prompt:" + user, function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            Session.submit("nope");
        });
        wait("failed:" + user, function () { return Session.state === "failed"; }, 2000, thenFn);
    }

    // Drives a failure straight through the mock, bypassing
    // Session.begin()/submit() entirely. Session's failure handling reacts
    // to backend signals regardless of what triggered them, so this still
    // exercises the real escalation math in onAuthFailure -- it just avoids
    // begin()'s blockedUntil gate, which would otherwise refuse every
    // attempt after the first once free=0 engages the block immediately,
    // making it impossible to observe growth across several failures
    // without actually waiting each delay out in real time.
    function directFail(thenFn) {
        action(function () {
            // Reset promptLabel/_state to a clean idle baseline first --
            // directFail() drives the mock directly and never goes through
            // begin(), so without this, the predicates below could resolve
            // instantly against leftover state from the *previous* cycle
            // (promptLabel still "Password:", _state still "failed")
            // instead of waiting for this cycle's real signal. That raced
            // mock.respond() ahead of this cycle's own createSession-fired
            // prompt, firing steps out of order -- exactly the kind of
            // cross-cycle contamination Session.cancel()/loadScenario()'s
            // timer cleanup exists to prevent.
            Session.cancel();
            mock.loadScenario("wrong-password");
            mock.createSession("michael");
        });
        wait("directPrompt", function () { return Session.promptLabel === "Password:"; }, 2000, function () {
            mock.respond("nope");
        });
        wait("directFailed", function () { return Session.state === "failed"; }, 2000, thenFn);
    }

    Component.onCompleted: {
        Session.backend = mock;

        if (!Session.backoffEnabled) {
            // --- mode 1: disabled (the shipping default) ---
            // No delay is ever applied and blockedUntil is never set, no
            // matter how many failures pile up; a wrong password is always
            // immediately retryable.
            fail("michael", function () {
                check("disabledNoBlockAfter1", Session.blockedUntil, 0);
            });
            fail("michael", function () {});
            fail("michael", function () {});
            fail("michael", function () {});
            fail("michael", function () {
                check("disabledNoBlockAfter5", Session.blockedUntil, 0);
                check("disabledFailuresStillCounted", Session.failures >= 1, true);
            });
            action(function () {
                Session.cancel();
                mock.loadScenario("wrong-password");
                Session.begin("michael");
                check("disabledImmediatelyRetryable", Session.state, "authenticating");
            });
        } else if (!Session.backoffPerUser) {
            // --- mode 2: enabled, global counter (bypassable by design) ---
            // The runner sets QSG_BACKOFF_FREE=0 for this invocation, so the
            // very first failure already crosses the free allowance.
            action(function () {
                Session.begin("michael"); // establishes root.user once, cleanly
                Session.cancel();
            });
            directFail(function () {
                check("globalBlockedAfterFree", Session.blockedUntil > 0, true);
            });
            var prevBlock = Session.blockedUntil;
            directFail(function () {
                check("globalDelayGrows", Session.blockedUntil >= prevBlock, true);
                prevBlock = Session.blockedUntil;
            });
            directFail(function () {
                check("globalDelayKeepsGrowing", Session.blockedUntil >= prevBlock, true);
            });
            directFail(function () {
                // start=1, max=4: the 4th post-free failure would be an
                // uncapped 8s delay if the ceiling were not applied. Checked
                // moments after the failure, so blockedUntil - now is still
                // close to whatever was just computed.
                var remaining = Session.blockedUntil - Math.floor(Date.now() / 1000);
                check("globalDelayCapped", remaining <= Session.backoffMax, true);
            });

            // A real begin() retry for the SAME username is refused while
            // blocked -- proves begin() actually honors blockedUntil.
            action(function () {
                Session.begin("michael");
                check("globalBeginRefusedWhileBlocked", Session.state, "failed");
            });

            // The bypass: switching the attempted username resets the
            // single shared counter, so a completely different name
            // proceeds immediately even though "michael" was just blocked.
            // This is documented, expected behavior for global mode --
            // pinned here so nobody later mistakes it for the safe one.
            action(function () {
                Session.begin("decoy");
                check("globalBypassUnblocksOnNameChange", Session.state, "authenticating");
                check("globalBypassResetsFailures", Session.failures, 0);
            });
            action(function () {
                Session.cancel();
                Session.begin("michael"); // switching back resets it again
                check("globalBypassStillUnblocked", Session.blockedUntil, 0);
            });
        } else {
            // --- mode 3: enabled, per-user counters (resists the bypass) ---
            // Default free/start/max (free=3) so failures 1-3 against
            // "michael" do not yet block, leaving room to interleave a
            // decoy between real attempts without hitting begin()'s
            // blockedUntil gate.
            fail("michael", function () {
                check("perUserAccumulates1", Session.failures, 1);
            });
            action(function () {
                Session.cancel();
                Session.begin("decoy");
                check("perUserDecoyStartsClean1", Session.failures, 0);
            });
            fail("michael", function () {
                check("perUserSurvivesInterleave1", Session.failures, 2);
            });
            action(function () {
                Session.cancel();
                Session.begin("decoy");
                check("perUserDecoyStartsClean2", Session.failures, 0);
            });
            fail("michael", function () {
                check("perUserSurvivesInterleave2", Session.failures, 3);
            });
            action(function () {
                Session.cancel();
                Session.begin("decoy");
                check("perUserDecoyStartsClean3", Session.failures, 0);
            });
            // This 4th failure against michael crosses free=3 and engages
            // the block -- the whole point of this mode is that the three
            // interleaved decoy attempts above never diluted it.
            fail("michael", function () {
                check("perUserSurvivesInterleave3", Session.failures, 4);
                check("perUserTargetBlocked", Session.blockedUntil > 0, true);
            });

            // The block belongs to "michael" specifically: a real retry for
            // "michael" is refused, but "decoy" (never blocked) proceeds
            // normally in the very next call.
            action(function () {
                Session.begin("michael");
                check("perUserBeginRefusedWhileBlocked", Session.state, "failed");
            });
            action(function () {
                Session.begin("decoy");
                check("perUserDecoyUnaffectedByTargetBlock", Session.state, "authenticating");
            });
        }

        drain();
    }
}
