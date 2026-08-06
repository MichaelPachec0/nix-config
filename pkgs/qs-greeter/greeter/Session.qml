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

    // Tunables, set from the module via env.
    readonly property int backoffFree: parseInt(Quickshell.env("QSG_BACKOFF_FREE") || "3", 10)
    readonly property int backoffStart: parseInt(Quickshell.env("QSG_BACKOFF_START") || "1", 10)
    readonly property int backoffMax: parseInt(Quickshell.env("QSG_BACKOFF_MAX") || "10", 10)
    readonly property int idleTimeoutSec: parseInt(Quickshell.env("QSG_IDLE_TIMEOUT") || "60", 10)

    signal launched()

    function begin(name) {
        if (!backend) { Log.error("no backend"); return; }
        if (Date.now() / 1000 < blockedUntil) return;
        root.user = name;
        root.statusText = "";
        root.statusIsError = false;
        root.waitingForDevice = false;
        root.promptLabel = "";
        root._state = "authenticating";
        idleTimer.restart();
        backend.createSession(name);
    }

    function submit(text) {
        if (_state !== "authenticating" || promptLabel === "") return;
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
            } else {
                // Info/error only. Quickshell acknowledges these itself; calling
                // respond() here would be refused and logged as critical.
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
            if (root.backend) root.backend.cancelSession();
            if (root.failures > root.backoffFree) {
                var n = root.failures - root.backoffFree - 1;
                var delay = Math.min(root.backoffStart * Math.pow(2, n), root.backoffMax);
                root.blockedUntil = Math.floor(Date.now() / 1000 + delay);
                Log.info("auth failure " + root.failures + ", blocked for " + delay + "s");
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
            if (root.backend && root._state !== "idle") root.backend.cancelSession();
            root._state = "idle";
        }
    }

    // A successful username change resets the penalty: the backoff exists to
    // slow a physical-console guesser, not to punish a typo in the user field.
    onUserChanged: { root.failures = 0; root.blockedUntil = 0; }
}
