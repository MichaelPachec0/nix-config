import QtQuick
import "../widgets" as Widgets

// The XP logon dialog. The two visible rows are chrome: PAM is a message
// loop, and the active (second) field binds to whatever PAM last asked for
// rather than assuming a password. That is what lets this stay a two-field
// dialog through 2FA, a PIN prompt, or a forced password change without
// knowing any of those exist -- it just relays session.promptLabel /
// session.promptSecret and shows session.statusText when there is no
// pending prompt at all.
//
// session/sessions are injected by Skin.qml exactly as shell.qml injects
// them into Skin.qml -- this file does not import the Session/Sessions
// singletons directly, so it can only ever see the object it was handed
// (the real one in production, a scripted MockBackend-driven one in the
// test below). Settings, CapsLock and GreeterState are cosmetic/local-state
// concerns, not privileged auth ones, so those ARE imported directly (see
// the local Settings.qml/CapsLock.qml/GreeterState.qml symlinks in this
// directory -- Quickshell's singleton registration is per-directory, so a
// bare reference from here needs its own link even though skins/xp/Skin.qml
// already has one; NOT called "State" -- QtQuick already has a built-in
// `State` element, and a same-named singleton is silently shadowed by it
// everywhere `import QtQuick` is in scope, i.e. everywhere. Confirmed the
// hard way: `State.save()` resolved to QtQuick's State and threw "Property
// 'save' of object QtQuick/State is not a function" instead of ever
// reaching this file's singleton).
Item {
    id: root
    required property var session
    required property var sessions
    required property var theme

    // Distinct from Skin.qml's requestPower(action): that fires an
    // already-decided systemctl action, and its three cases (poweroff,
    // reboot, else-suspend) have no "show me the choices" branch. This
    // fires the intent; Task 11's ShutDownDialog is the thing that turns a
    // user's actual pick into a requestPower() call.
    signal shutDownRequested()

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight
    width: implicitWidth
    height: implicitHeight

    focus: true
    Keys.onEscapePressed: root._cancel()
    Keys.onReturnPressed: root._ok()

    // --- the active field: chrome bound to whatever PAM last asked for ---
    readonly property bool _authenticating: !!root.session && root.session.state === "authenticating"
    readonly property string activeLabel: (root._authenticating && root.session.promptLabel)
        ? root.session.promptLabel : "Password:"
    readonly property bool activeEcho: !!root.session && root.session.promptSecret

    // --- backoff countdown ---
    // A plain polled clock, not a binding on Date.now() directly (a
    // property binding that reads Date.now() only evaluates once, at bind
    // time -- it has no way to know a clock tick should re-run it. Session's
    // own backoffTimer uses the same 250ms poll for the same reason).
    property double _nowSec: Date.now() / 1000
    Timer {
        interval: 250
        repeat: true
        running: !!root.session && root.session.blockedUntil > 0
        onTriggered: root._nowSec = Date.now() / 1000
    }
    readonly property bool blocked: !!root.session && root.session.blockedUntil > root._nowSec

    // --- status line: backoff countdown, else the waiting-for-device hint,
    // else whatever Session last said. In that priority order, always. ---
    readonly property string statusLineText: {
        if (root.blocked) {
            var remain = Math.max(0, Math.ceil(root.session.blockedUntil - root._nowSec));
            return "Too many attempts. Try again in " + remain + "s.";
        }
        if (!!root.session && root.session.waitingForDevice)
            return "Waiting for your security key...";
        return (!!root.session && root.session.statusText) || "";
    }

    // --- session picker: combo selection wins if the user touched it,
    // else Settings' configured default, else the last session actually
    // launched, else whatever sorts first (shells sort last -- see
    // wrapper/sessions-parse.sh, which appends them after the graphical
    // and extra entries, so "first" here already means "first graphical"
    // in the common case). ---
    property bool optionsExpanded: false
    property bool _comboUserSet: false

    function _sessionNames() {
        return (!!root.sessions && root.sessions.list ? root.sessions.list : [])
            .map(function (s) { return s.name; });
    }

    function _defaultSessionIndex() {
        var names = root._sessionNames();
        if (names.length === 0) return -1;
        var cfgSessions = Settings.config && Settings.config.sessions;
        var def = cfgSessions ? cfgSessions.default : null;
        if (def) {
            var i = names.indexOf(def);
            if (i >= 0) return i;
        }
        if (GreeterState.lastSession) {
            var j = names.indexOf(GreeterState.lastSession);
            if (j >= 0) return j;
        }
        return 0;
    }

    function _syncComboDefault() {
        if (root._comboUserSet) return;
        combo.currentIndex = root._defaultSessionIndex();
    }

    // Every async source the default can legitimately come from: the
    // session list arriving (Sessions.ready/list), the settings merge
    // settling (Settings.ready), and GreeterState's own file load resolving
    // lastSession sometime after this component completes. Component-local
    // Connections rather than a plain `currentIndex: ...` binding on the
    // combo itself, because that binding would have to read currentIndex
    // to decide whether to keep it (once the user has picked something) --
    // a property binding that reads the very property it assigns is a
    // self-reference QML flags as a binding loop, not a stable no-op.
    Connections {
        target: root.sessions
        function onListChanged() { root._syncComboDefault(); }
        function onReadyChanged() { root._syncComboDefault(); }
    }
    Connections {
        target: Settings
        function onReadyChanged() { root._syncComboDefault(); }
    }
    Connections {
        target: GreeterState
        function onLastSessionChanged() { root._syncComboDefault(); }
    }
    Component.onCompleted: root._syncComboDefault()

    function _resolveEntry() {
        var list = (!!root.sessions && root.sessions.list) || [];
        if (combo.currentIndex >= 0 && combo.currentIndex < list.length)
            return list[combo.currentIndex];
        var idx = root._defaultSessionIndex();
        return idx >= 0 ? list[idx] : null;
    }

    function _pickerEnabled() {
        var cfgSessions = Settings.config && Settings.config.sessions;
        return !!(cfgSessions && cfgSessions.picker);
    }

    function toggleOptions() {
        if (!root._pickerEnabled()) return;
        root.optionsExpanded = !root.optionsExpanded;
    }

    // --- actions ---
    function _ok() {
        // Session.begin() already refuses to start a new attempt while
        // blockedUntil is in the future (and submit() can only ever be
        // reached from "authenticating", which begin() cannot enter while
        // blocked either -- so this condition cannot occur through normal
        // Session-owned flow). The explicit check here is belt-and-braces
        // so the OK button's disabled state and the Enter-key path (Keys.
        // onReturnPressed / each field's onAccepted, both of which call
        // this function directly and do not go through the button's own
        // `enabled` at all) agree with each other, not just with Session.
        if (!root.session || root.blocked) return;
        if (root.session.state === "idle" || root.session.state === "failed")
            root.session.begin(userField.text);
        else
            root.session.submit(secretField.text);
    }

    function _cancel() {
        if (root.session) root.session.cancel();
        secretField.text = "";
    }

    function _launchSelected() {
        var entry = root._resolveEntry();
        if (!entry) return;
        // session.user, not userField.text: session.user is what actually
        // authenticated (begin() is what sets it), so this stays correct
        // even for a caller that drives Session directly rather than
        // through this field (every test in this plan does; a future
        // caller might too) -- the two happen to always agree for a real
        // click, since OK's own handler reads userField.text into begin()
        // in the first place, but there is no reason to route back through
        // the widget for a value Session already owns authoritatively.
        GreeterState.lastUser = root.session.user;
        GreeterState.lastSession = entry.name;
        GreeterState.save();
        root.session.launch(entry);
    }

    Connections {
        target: root.session
        function onStateChanged() {
            if (!root.session) return;
            if (root.session.state === "ready") {
                // Deferred via Qt.callLater, not called inline: launch()
                // immediately writes session.state again (to "launching"),
                // and doing that synchronously from inside THIS handler --
                // itself dispatched because state just changed to "ready"
                // -- is a reentrant write to the same property from within
                // its own change notification. Confirmed empirically: Qt's
                // QML engine flags that shape as "Binding loop detected
                // for property state" and, worse than just logging it,
                // actually suppresses the write, which left session.state
                // wedged at "ready" forever (launch() ran, but its own
                // _state = "launching" assignment never took). Deferring
                // to the next event-loop turn breaks the reentrancy.
                Qt.callLater(root._launchSelected);
            } else if (root.session.state === "failed") {
                secretField.text = "";
                msgBox.text = "The system could not log you on. Make sure your "
                    + "User name and password are correct.";
                msgBox.visible = true;
            }
        }
    }

    // --- exposed for headless testing only (same convention as
    // XpButton.pulseRunning / XpComboBox.highlightIndex: a child's own
    // property, not otherwise reachable from outside this file, aliased
    // out under a name that says what it is for). ---
    readonly property alias testUserFieldText: userField.text
    readonly property alias testUserFieldEnabled: userField.enabled
    readonly property alias testUserRowHeight: userField.height
    readonly property alias testSecretFieldLabel: secretField.label
    readonly property alias testSecretFieldEchoMode: secretField.echoMode
    readonly property alias testSecretFieldText: secretField.text
    readonly property alias testSecretRowHeight: secretField.height
    readonly property alias testStatusRowHeight: statusText.height
    readonly property alias testComboVisible: sessionRow.visible
    readonly property alias testComboModel: combo.model
    readonly property alias testComboCurrentName: combo.currentName
    readonly property alias testMsgBoxVisible: msgBox.visible
    readonly property alias testMsgBoxText: msgBox.text
    readonly property alias testCapsBalloonVisible: capsBalloon.visible
    readonly property bool testOkEnabled: !root.blocked
    function testSelectSessionByName(name) {
        var names = root._sessionNames();
        var idx = names.indexOf(name);
        if (idx < 0) return;
        combo.currentIndex = idx;
        root._comboUserSet = true;
    }

    Item {
        id: content
        implicitWidth: rows.implicitWidth
        implicitHeight: rows.implicitHeight

        Column {
            id: rows
            width: parent.width
            spacing: root.theme.rowSpacing

            Widgets.XpTextField {
                id: userField
                theme: root.theme
                label: "User name:"
                text: GreeterState.lastUser
                width: parent.width
                enabled: !root.session
                    || root.session.state === "idle"
                    || root.session.state === "failed"
                onAccepted: root._ok()
            }

            Widgets.XpTextField {
                id: secretField
                theme: root.theme
                label: root.activeLabel
                echo: root.activeEcho
                width: parent.width
                enabled: !!root.session
                    && root.session.state !== "ready"
                    && root.session.state !== "launching"
                onAccepted: root._ok()
            }

            // Collapsed (Column skips invisible children entirely, so this
            // contributes nothing to layout height) until Options is
            // toggled -- and only reachable when Settings' picker flag is
            // on (see toggleOptions()), so optionsExpanded can never
            // become true otherwise.
            Column {
                id: sessionRow
                width: parent.width
                visible: root.optionsExpanded
                spacing: root.theme.rowSpacing / 2

                Text {
                    text: "Log on to:"
                    color: root.theme.infoText
                    font.family: root.theme.uiBold
                    font.bold: true
                    font.pixelSize: root.theme.uiSize
                }
                Widgets.XpComboBox {
                    id: combo
                    theme: root.theme
                    model: root._sessionNames()
                    onActivated: root._comboUserSet = true
                }
            }

            // The one row allowed to change height as auth state moves --
            // everything above it (banner, both field rows) is fixed, so
            // the dialog never jumps mid-auth. Its own height still only
            // ever varies with how many lines its (short, single-sentence)
            // text wraps to, never with an added/removed sibling.
            Text {
                id: statusText
                width: parent.width
                text: root.statusLineText
                wrapMode: Text.WordWrap
                color: (!!root.session && root.session.statusIsError && !root.blocked
                    && !root.session.waitingForDevice) ? root.theme.errorText : root.theme.infoText
                font.family: root.theme.ui
                font.pixelSize: root.theme.uiSize
            }
        }
    }

    Widgets.XpDialog {
        id: dialog
        theme: root.theme
        bannerTitle: (Settings.config.branding && Settings.config.branding.title) || "Log On to Windows"
        bannerSubtitle: (Settings.config.branding && Settings.config.branding.subtitle) || ""
        contentItem: content
        // Rebuilding this array (and so the button row) whenever `blocked`
        // flips is inherent to XpDialog's own buttons-array API (any
        // binding read inside this literal makes the whole literal
        // re-evaluate, the same way its own `enabled` per-button field is
        // designed to be driven) -- not a workaround specific to this file.
        // `blocked` only flips a few times total during an actual lockout,
        // not every tick of the 250ms countdown poll.
        buttons: [
            { text: "OK", isDefault: true, enabled: !root.blocked,
              onClicked: function () { root._ok(); } },
            { text: "Cancel",
              onClicked: function () { root._cancel(); } },
            { text: "Shut Down...",
              onClicked: function () { root.shutDownRequested(); } },
            { text: "Options >>",
              onClicked: function () { root.toggleOptions(); } }
        ]
    }

    Widgets.XpBalloon {
        id: capsBalloon
        theme: root.theme
        visible: CapsLock.on
        text: "Caps Lock is on."
        target: secretField
    }

    Widgets.XpMessageBox {
        id: msgBox
        theme: root.theme
        visible: false
        z: 10
        anchors.centerIn: dialog
        onAccepted: visible = false
    }
}
