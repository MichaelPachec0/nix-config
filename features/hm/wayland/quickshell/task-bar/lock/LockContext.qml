// features/hm/wayland/quickshell/task-bar/lock/LockContext.qml
// Shared auth state across all lock surfaces. Mirrors end4 LockContext.qml,
// adapted: no GlobalStates, no fingerprint/keyring (MVP), targets the
// quickshell-lock PAM service. SECURITY-RELEVANT -- keep faithful to the ref.
import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked()
    signal failed()

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property int failCount: 0
    property string statusMessage: ""
    property bool statusIsError: false

    // Overridable so a headless harness can point PAM at a test service.
    // Defaults are the real lock service; production callers set neither.
    property string pamConfig: "quickshell-lock"
    property string pamConfigDirectory: "/etc/pam.d"

    // Silent-worker backstop cap, in ms. Overridable so a headless harness
    // can shrink it to keep the timeout test fast. quickshell-lock has
    // u2fAuth enabled, so a live worker can legitimately go quiet for the
    // length of one physical touch; 60s covers a realistic single touch.
    // See the authTimeout Timer below for what actually resets this.
    property int authTimeoutMs: 60000

    // True from the moment authTimeout finalizes an attempt until the next
    // tryUnlock() starts a new one. Guards against a completion that still
    // arrives for the transaction the timeout already gave up on.
    property bool timedOut: false

    function clearText() { root.currentText = ""; }

    function _capitalize(s) {
        return (s && s.length > 0) ? s.charAt(0).toUpperCase() + s.slice(1) : s;
    }

    function reset() {
        root.clearText();
        root.unlockInProgress = false;
        root.showFailure = false;
        root.statusMessage = "";
        root.statusIsError = false;
        statusClearTimer.stop();
        authTimeout.stop();
        root.timedOut = false;
    }

    function tryUnlock() {
        if (root.unlockInProgress) return;
        root.statusMessage = "";
        root.statusIsError = false;
        root.unlockInProgress = true;
        root.timedOut = false;
        pam.start();
        authTimeout.restart();
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) root.showFailure = false;
        passwordClearTimer.restart();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        // Same interval as authTimeout by coincidence (a typed-then-idle
        // password and a just-started attempt both age out around 10s).
        // While a PAM transaction is in flight, authTimeout owns the
        // timeout: it aborts, records the failure and re-arms. A plain
        // reset() here would race it, clearing unlockInProgress without
        // aborting the worker or reporting a failure, silently orphaning
        // the PAM subprocess.
        onTriggered: {
            if (!root.unlockInProgress) root.reset();
        }
    }

    Timer {
        id: statusClearTimer
        interval: 5000
        onTriggered: { root.statusMessage = ""; root.statusIsError = false; }
    }

    // Worker-silence detector, not a wall-clock attempt cap. Fires only
    // after authTimeoutMs of TOTAL PAM SILENCE -- every onPamMessage (a u2f
    // touch cue, a prompt, anything) restarts it, because a worker still
    // talking is a live worker. A worker that dies without delivering a
    // completion (crash, EPIPE, reporter holding the pipe) goes silent and
    // never fires onCompleted, so unlockInProgress would otherwise stick
    // true forever, wedging the lock; this re-arms the field instead. A
    // legitimate slow step (waiting on a physical u2f touch) is not
    // silence as long as the worker keeps emitting messages, so it is not
    // penalized by this timer -- authTimeoutMs is the backstop for an
    // actually-dead worker, not a per-attempt deadline. Fail-closed: it
    // never unlocks.
    Timer {
        id: authTimeout
        interval: root.authTimeoutMs
        repeat: false
        onTriggered: {
            root.timedOut = true;
            pam.abort();
            root.unlockInProgress = false;
            root.clearText();
            root.showFailure = true;
            root.failCount += 1;
            root.statusMessage = "Authentication timed out";
            root.statusIsError = true;
            statusClearTimer.restart();
            root.failed();
        }
    }

    PamContext {
        id: pam
        configDirectory: root.pamConfigDirectory
        config: root.pamConfig
        // user defaults to the current user

        onPamMessage: {
            authTimeout.restart();
            if (this.responseRequired) {
                this.respond(root.currentText);
            } else {
                // Info/Error PAM message (u2f touch cue, fingerprint prompt,
                // failed-match). Surface it ReGreet-style: capitalized, errors
                // flagged; auto-clears after 5s. Does NOT affect what unlocks.
                root.statusMessage = root._capitalize(this.message);
                root.statusIsError = this.messageIsError;
                statusClearTimer.restart();
            }
        }
        onCompleted: result => {
            authTimeout.stop();
            if (root.timedOut) {
                // authTimeout already finalized this transaction (aborted
                // the worker, counted the failure, re-armed, and reported
                // "Authentication timed out"). A completion that still
                // arrives after that -- observed not to happen on this
                // quickshell build, but not guaranteed by the API -- must
                // not double-count failCount, re-emit failed(), or
                // overwrite the timeout's status message with a blank one.
                return;
            }
            if (result === PamResult.Success) {
                root.unlockInProgress = false;
                root.unlocked();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                root.showFailure = true;
                root.failCount += 1;
                root.statusMessage = "";
                root.statusIsError = false;
                root.failed();
            }
        }
    }
}
