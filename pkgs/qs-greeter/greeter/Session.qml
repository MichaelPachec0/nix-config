pragma Singleton
import QtQuick
import Quickshell

// The greetd conversation, modeled as a message loop rather than as a
// username/password form. The skin's two visible rows are chrome; the active
// field binds to whatever PAM last asked for, which is what lets a two-field
// XP dialog survive 2FA, a PIN prompt, or a forced password change.
Singleton {
    id: root

    property var backend: null

    readonly property string state: _state
    property string _state: "idle"

    property string user: ""
    property string promptLabel: ""
    property bool promptSecret: true
    property string statusText: ""
    property bool statusIsError: false
    property bool waitingForDevice: false
    property int failures: 0
    property int blockedUntil: 0
    // Set the instant a response-required message arrives, cleared the
    // instant submit() sends an answer for it. This -- not promptLabel --
    // is what submit() gates on: an info/error message (responseRequired
    // false) leaves promptLabel holding the previous prompt's text, so
    // gating on "promptLabel non-empty" would let a submit() land during
    // that window and call backend.respond() with nothing pending, which
    // quickshell refuses with a qCCritical.
    property bool _responsePending: false

    // Tunables, set from the module via env.
    readonly property int backoffFree: parseInt(Quickshell.env("QSG_BACKOFF_FREE") || "3", 10)
    readonly property int backoffStart: parseInt(Quickshell.env("QSG_BACKOFF_START") || "1", 10)
    readonly property int backoffMax: parseInt(Quickshell.env("QSG_BACKOFF_MAX") || "10", 10)
    readonly property int idleTimeoutSec: parseInt(Quickshell.env("QSG_IDLE_TIMEOUT") || "60", 10)
    // Backoff is off by default (see auth.backoff.enable/perUser in the Nix
    // module): the original single-counter design reset on every username
    // change, which alternating the attempted name between guesses defeats
    // completely (reproduced 5/5 in review). perUser tracks failures and
    // blockedUntil keyed to the attempted username instead of in one shared
    // counter, which is what actually resists that bypass; global keeps the
    // original bypassable behavior available for callers who still want it.
    readonly property bool backoffEnabled: _envBool("QSG_BACKOFF_ENABLE")
    readonly property bool backoffPerUser: _envBool("QSG_BACKOFF_PERUSER")
    // Per-username failures/blockedUntil, used only when backoffPerUser is
    // true. Absent (disabled) or malformed env values are treated as off.
    property var _perUserFailures: ({})
    property var _perUserBlockedUntil: ({})

    function _envBool(name) {
        var v = Quickshell.env(name);
        return v === "1" || v === "true";
    }

    signal launched()

    function begin(name) {
        if (!backend) { Log.error("no backend"); return; }
        // Assign the name first so a per-user blockedUntil check below (via
        // onUserChanged, which loads that username's own counters) reflects
        // the account actually being attempted, not whichever account was
        // active before this call.
        root.user = name;
        if (Date.now() / 1000 < root.blockedUntil) return;
        root.statusText = "";
        root.statusIsError = false;
        root.waitingForDevice = false;
        root.promptLabel = "";
        root._responsePending = false;
        root._state = "authenticating";
        idleTimer.restart();
        backend.createSession(name);
    }

    function submit(text) {
        if (_state !== "authenticating" || !_responsePending) return;
        root._responsePending = false;
        silentTimer.restart();
        idleTimer.restart();
        backend.respond(text);
    }

    function cancel() {
        silentTimer.stop();
        idleTimer.stop();
        if (backend && _state !== "idle") backend.cancelSession();
        root._state = "idle";
        root.promptLabel = "";
        root._responsePending = false;
        root.waitingForDevice = false;
    }

    function launch(entry) {
        if (_state !== "ready") return;
        var env = [];
        for (var k in (entry.env || {})) env.push(k + "=" + entry.env[k]);
        root._state = "launching";
        Log.info("launching session: " + entry.name);
        backend.launch(entry.argv, env, true);
    }

    // No message has arrived since the last respond(). pam_u2f without `cue`
    // blocks silently on the token, so a frozen-looking dialog is the default
    // failure. A timeout is used rather than reading the PAM stack, so this
    // does not break when the PAM config changes.
    Timer {
        id: silentTimer
        interval: 1500
        repeat: false
        onTriggered: if (root._state === "authenticating") root.waitingForDevice = true;
    }

    Timer {
        id: idleTimer
        interval: root.idleTimeoutSec * 1000
        repeat: false
        onTriggered: {
            if (root._state === "authenticating") {
                Log.info("idle timeout, cancelling the pending session");
                root.cancel();
            }
        }
    }

    Timer {
        id: backoffTimer
        interval: 250
        repeat: true
        running: root.blockedUntil > 0
        onTriggered: if (Date.now() / 1000 >= root.blockedUntil) {
            root.blockedUntil = 0;
            running = false;
        }
    }

    property var _conn: Connections {
        target: root.backend
        ignoreUnknownSignals: true

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            silentTimer.stop();
            root.waitingForDevice = false;
            idleTimer.restart();
            // Never log a response; the prompt and its flags are safe.
            Log.debug("authMessage flags: error=" + error
                + " responseRequired=" + responseRequired
                + " echoResponse=" + echoResponse);
            if (responseRequired) {
                root.promptLabel = message;
                root.promptSecret = !echoResponse;
                root._responsePending = true;
            } else {
                // Info/error only. Quickshell acknowledges these itself; calling
                // respond() here would be refused and logged as critical.
                // _responsePending is untouched -- greetd only ever has one
                // message outstanding at a time, so it is already false here.
                root.statusText = message;
                root.statusIsError = error;
            }
        }

        function onAuthFailure(message) {
            silentTimer.stop();
            idleTimer.stop();
            root.failures += 1;
            root._state = "failed";
            root.statusText = message;
            root.statusIsError = true;
            root.promptLabel = "";
            root._responsePending = false;
            if (root.backend) root.backend.cancelSession();
            if (root.backoffEnabled && root.failures > root.backoffFree) {
                var n = root.failures - root.backoffFree - 1;
                var delay = Math.min(root.backoffStart * Math.pow(2, n), root.backoffMax);
                root.blockedUntil = Math.floor(Date.now() / 1000 + delay);
                Log.info("auth failure " + root.failures + ", blocked for " + delay + "s");
            }
            if (root.backoffEnabled && root.backoffPerUser) {
                root._perUserFailures[root.user] = root.failures;
                root._perUserBlockedUntil[root.user] = root.blockedUntil;
            }
        }

        function onReadyToLaunch() {
            silentTimer.stop();
            idleTimer.stop();
            root.waitingForDevice = false;
            root._state = "ready";
        }

        function onLaunched() {
            root._state = "launched";
            root.launched();
        }

        function onError(message) {
            silentTimer.stop();
            idleTimer.stop();
            Log.error("greetd error: " + message);
            root.statusText = message;
            root.statusIsError = true;
            root._responsePending = false;
            if (root.backend && root._state !== "idle") root.backend.cancelSession();
            root._state = "idle";
        }
    }

    // What a username change does to the failure/backoff state depends on
    // the mode:
    //   - disabled: backoff never applies regardless, but a stale
    //     blockedUntil must never survive a name change.
    //   - global (backoffEnabled && !backoffPerUser): the plan's original,
    //     bypassable semantics -- one shared counter, wiped on every name
    //     change. Kept available on purpose; see auth.backoff.perUser.
    //   - perUser (backoffEnabled && backoffPerUser): swap in the new
    //     username's own counters instead of wiping them, so guesses
    //     against one account accumulate no matter what else was typed in
    //     between.
    onUserChanged: {
        if (!root.backoffEnabled) {
            root.failures = 0;
            root.blockedUntil = 0;
            return;
        }
        if (root.backoffPerUser) {
            root.failures = root._perUserFailures[root.user] || 0;
            root.blockedUntil = root._perUserBlockedUntil[root.user] || 0;
        } else {
            root.failures = 0;
            root.blockedUntil = 0;
        }
    }
}
