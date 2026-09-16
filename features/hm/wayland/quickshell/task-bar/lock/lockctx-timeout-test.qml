// Headless harness: drive LockContext against a hanging PAM service and
// prove (1) the auth timeout re-arms the context, (2) a late completion for
// the aborted attempt is not double-counted, (3) the context is actually
// USABLE again -- a fresh attempt against a fast service reaches a clean
// completion, and (4) the timeout is a silent-worker detector, not a
// wall-clock cap -- a worker still emitting PAM messages resets the deadline
// instead of being aborted mid-conversation. Not shipped to any real lock
// surface.
import QtQuick
import Quickshell

ShellRoot {
    LockContext {
        id: ctx
        pamConfigDirectory: Quickshell.env("QS_TEST_PAM_DIR")
        pamConfig: "hang"
        // Shrunk from the 60000ms production default so the silent-hang
        // and reset-on-message cases both resolve in seconds, not minutes.
        authTimeoutMs: 2000

        property string phase: "first"
        property double resetProbeStart: 0

        Component.onCompleted: {
            console.log("TEST START");
            ctx.currentText = "irrelevant";
            ctx.tryUnlock();
        }

        Connections {
            target: ctx
            function onFailed() {
                if (ctx.phase === "first") {
                    // authTimeout fired: prove re-arm, then hold here for a
                    // beat to prove no LATE completion from the aborted
                    // "hang" transaction sneaks in and double-counts before
                    // we move on (Finding 2 regression guard).
                    console.log("TEST REARMED unlockInProgress="
                        + ctx.unlockInProgress + " failCount=" + ctx.failCount);
                    ctx.phase = "watching";
                    watchTimer.restart();
                } else if (ctx.phase === "watching") {
                    console.log("TEST WATCH VIOLATION doubleFailCount failCount="
                        + ctx.failCount);
                    ctx.phase = "done";
                } else if (ctx.phase === "second") {
                    // The second, independent attempt reached a clean
                    // completion (fast, via PamContext.onCompleted, not via
                    // another authTimeout) -- proves the first abort() did
                    // not orphan the worker/pipe for the next attempt
                    // (Finding 1: the lock is actually usable again).
                    console.log("TEST SECOND COMPLETED result=failed failCount="
                        + ctx.failCount);
                    ctx.phase = "resetProbe";
                    ctx.resetProbeStart = Date.now();
                    ctx.pamConfig = "livehang";
                    ctx.tryUnlock();
                } else if (ctx.phase === "resetProbe") {
                    // "livehang" emits one PAM message partway through its
                    // first second, then keeps hanging. authTimeoutMs is
                    // 2000ms: if onPamMessage did NOT restart authTimeout,
                    // this fires at ~2000ms from tryUnlock(). If it DID
                    // restart, the deadline moved to (message time)+2000ms,
                    // so this fires well past 2000ms -- comfortably past
                    // authTimeoutMs plus margin proves the reset happened.
                    var delta = Date.now() - ctx.resetProbeStart;
                    if (delta > ctx.authTimeoutMs + 500) {
                        console.log("TEST RESET-ON-MESSAGE OK delta=" + delta + "ms");
                    } else {
                        console.log("TEST RESET-ON-MESSAGE FAIL delta=" + delta + "ms");
                    }
                    ctx.phase = "done";
                }
            }
            function onUnlocked() {
                if (ctx.phase === "second") {
                    console.log("TEST SECOND COMPLETED result=success");
                    ctx.phase = "resetProbe";
                    ctx.resetProbeStart = Date.now();
                    ctx.pamConfig = "livehang";
                    ctx.tryUnlock();
                } else {
                    console.log("TEST UNEXPECTED UNLOCK");
                }
            }
        }

        Timer {
            id: watchTimer
            interval: 4000
            repeat: false
            onTriggered: {
                if (ctx.phase === "watching") {
                    console.log("TEST WATCH OK failCount=" + ctx.failCount);
                    ctx.phase = "second";
                    ctx.pamConfig = "quick";
                    ctx.tryUnlock();
                }
            }
        }
    }
}
