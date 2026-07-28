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

    function clearText() { root.currentText = ""; }

    function reset() {
        root.clearText();
        root.unlockInProgress = false;
        root.showFailure = false;
    }

    function tryUnlock() {
        if (root.unlockInProgress) return;
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

    PamContext {
        id: pam
        configDirectory: "/etc/pam.d"
        config: "quickshell-lock"
        // user defaults to the current user

        onPamMessage: {
            if (this.responseRequired) this.respond(root.currentText);
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
                root.failed();
            }
        }
    }
}
