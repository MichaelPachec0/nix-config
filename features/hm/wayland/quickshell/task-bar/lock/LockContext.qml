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
    }

    function tryUnlock() {
        if (root.unlockInProgress) return;
        root.statusMessage = "";
        root.statusIsError = false;
        root.unlockInProgress = true;
        pam.start();
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) root.showFailure = false;
        passwordClearTimer.restart();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: root.reset()
    }

    Timer {
        id: statusClearTimer
        interval: 5000
        onTriggered: { root.statusMessage = ""; root.statusIsError = false; }
    }

    PamContext {
        id: pam
        configDirectory: "/etc/pam.d"
        config: "quickshell-lock"
        // user defaults to the current user

        onPamMessage: {
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
