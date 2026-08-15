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
// session/sessions/theme/settings/capsLock/greeterState are all injected by
// Skin.qml, which itself only ever received them from shell.qml -- this
// file imports none of the underlying singletons directly. That used to be
// true only for session/sessions ("privileged auth" ones); Settings,
// CapsLock and GreeterState were bare-referenced directly instead, on the
// theory that they are cosmetic/local-state concerns and this directory
// carries its own Settings.qml/CapsLock.qml/GreeterState.qml symlinks so
// the reference would resolve. It compiled and ran fine under every
// headless dev/tests/ suite and was still wrong: this file (like all of
// skins/xp/) is reached in production only through shell.qml's Loader,
// whose `source` is a runtime-computed path string, never a static
// `import` -- and Quickshell only registers a directory for bare singleton
// access by walking the textual `import` graph from the shell's actual
// entrypoint (see scan.cpp's scanQmlFile/scanDir). A directory a Loader
// reaches dynamically is invisible to that walk no matter what symlinks
// sit in it, so every bare Settings/CapsLock/GreeterState reference here
// threw "ReferenceError: <name> is not defined" against the real built
// package (confirmed with a standalone `qs -p` repro) while silently
// passing every dev/tests/ suite, which reaches this same file through a
// STATIC directory import from an entrypoint that happens to sit right
// next to its own copies of these symlinks. Injection sidesteps the whole
// per-directory-registration question the same way it already did for
// session/sessions: an object reference handed down explicitly does not
// care which directory anyone's `import` graph does or does not cover.
//
// NOT called "State" -- QtQuick already has a built-in `State` element, and
// a same-named singleton is silently shadowed by it everywhere `import
// QtQuick` is in scope, i.e. everywhere. Confirmed the hard way:
// `State.save()` resolved to QtQuick's State and threw "Property 'save' of
// object QtQuick/State is not a function" instead of ever reaching this
// file's singleton).
Item {
    id: root
    required property var session
    required property var sessions
    required property var theme
    // May legitimately be null (e.g. a test driving this file standalone
    // with no Settings/GreeterState/CapsLock fixture) -- every read below
    // is guarded the same way the pre-existing session/sessions reads are.
    required property var settings
    required property var greeterState
    required property var capsLock

    // Distinct from Skin.qml's requestPower(action): that fires an
    // already-decided systemctl action, and its three cases (poweroff,
    // reboot, else-suspend) have no "show me the choices" branch. This
    // fires only the intent to see the choices; Skin.qml owns
    // `shutDownVisible` and, on this signal, shows screens/
    // ShutDownDialog.qml -- the thing that turns a user's actual pick into
    // a requestPower() call. This file never talks to ShutDownDialog.qml
    // directly (it does not import screens/ -- there is nothing there to
    // import from itself), which keeps the same session/sessions-only
    // privilege boundary this file's own header describes: the dialog that
    // can reboot or power off the machine is entirely Skin.qml's concern.
    signal shutDownRequested()

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // Conditional, not a bare `true`: Skin.qml constructs this screen
    // eagerly and shows it via `visible: !root._fatal`, so it is built but
    // HIDDEN whenever greetd is unavailable or no sessions loaded (routed
    // to SkinFatal.qml instead) -- exactly the same "built before it is
    // shown" shape as ShutDownDialog.qml, and the same fix applies for the
    // same reason: a hidden dialog must not hold a focus claim on a screen
    // whose whole job is routing keystrokes to the PAM field.
    focus: root.visible
    Keys.onEscapePressed: root._cancel()
    Keys.onReturnPressed: root._ok()

    // Nothing has keyboard focus at boot without this: `focus: root.visible`
    // above only ever routes Enter/Escape (this Item's own Keys.on*
    // handlers) -- it does not, by itself, give either XpTextField's inner
    // TextInput the actual character-level activeFocus a login screen
    // needs. XpTextField.forceFocus() exists for exactly this and
    // previously had zero callers. Gated on root.visible, never
    // unconditional, matching the same hidden-dialog rule the comment
    // above already states for `focus: root.visible` itself: a hidden
    // dialog (behind SkinFatal) must never steal a focus claim. This
    // covers the dialog becoming visible after starting hidden (greetd or
    // the session list arriving late); the Component.onCompleted near the
    // bottom of this file (QML permits only one per object, so it is
    // merged with the pre-existing combo-default sync there rather than
    // duplicated here) covers the common case where it is visible from the
    // very first frame.
    onVisibleChanged: if (root.visible) userField.forceFocus();

    // Final micro-fix, second item: Skin.qml disables this dialog while
    // the Shut Down modal is up (`enabled: !root.shutDownVisible`) rather
    // than hiding it -- `visible` never changes, only opacity does, so
    // neither the claim above nor Component.onCompleted's ever fires for
    // this transition. Qt clears activeFocus when an item is disabled and
    // does NOT restore it when the item is re-enabled, so cancelling that
    // modal left the keyboard dead until the user clicked a field. Same
    // conditional pattern as every other claim in this file: gated on
    // visible && enabled (enabled is read explicitly here, not implied by
    // firing only on enabledChanged, so a future caller that disables this
    // dialog for some other reason while it happens to already be enabled
    // cannot steal a claim it should not have), reusing the existing
    // built-in enabledChanged signal rather than adding a new one.
    onEnabledChanged: if (root.visible && root.enabled) userField.forceFocus();

    // The other half of F1/F4: the instant PAM asks a new response-required
    // question, move focus to the field that answers it and clear whatever
    // text a PREVIOUS prompt left behind, strictly before this prompt's own
    // echo mode (session.promptSecret, read through activeEcho below) can
    // apply to that leftover text -- session.promptArriving() fires before
    // Session.qml assigns promptLabel/promptSecret for exactly this
    // ordering (see its own comment). Without this, an echo-off prompt
    // (e.g. a PIN) followed by an echo-on prompt re-renders whatever the
    // user typed for the FIRST prompt in cleartext on a pre-auth screen.
    Connections {
        target: root.session
        function onPromptArriving() {
            secretField.text = "";
            if (root.visible) secretField.forceFocus();
        }
    }

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
    // Initial value only -- toggleOptions() below assigns this property
    // directly, and a plain imperative assignment permanently tears down
    // whatever declarative binding a property started with (standard QML
    // behavior), so this binding only ever governs the very first render;
    // after that it is free-toggle state exactly as before. Settings.config
    // starts as an empty object before Settings.ready settles, so this
    // reads false at construction and re-evaluates once the real config
    // lands (Settings.config is reassigned wholesale on settle, which
    // re-fires this binding's dependency the same way _syncComboDefault()'s
    // own Settings.onReadyChanged connection reacts to the same settle).
    property bool optionsExpanded: !!(root.settings && root.settings.config && root.settings.config.optionsExpanded)
    property bool _comboUserSet: false

    // One accessor for every branding string, so the six bindings that feed
    // the brand panel do not each re-spell the same four-level guarded
    // lookup into Settings.config.
    function _brand(key) {
        var b = root.settings && root.settings.config && root.settings.config.branding;
        return (b && typeof b[key] === "string") ? b[key] : "";
    }

    function _sessionNames() {
        return (!!root.sessions && root.sessions.list ? root.sessions.list : [])
            .map(function (s) { return s.name; });
    }

    function _defaultSessionIndex() {
        var names = root._sessionNames();
        if (names.length === 0) return -1;
        var cfgSessions = root.settings && root.settings.config && root.settings.config.sessions;
        var def = cfgSessions ? cfgSessions.default : null;
        if (def) {
            var i = names.indexOf(def);
            if (i >= 0) return i;
        }
        if (root.greeterState && root.greeterState.lastSession) {
            var j = names.indexOf(root.greeterState.lastSession);
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
        target: root.settings
        function onReadyChanged() { root._syncComboDefault(); }
    }
    Connections {
        target: root.greeterState
        function onLastSessionChanged() { root._syncComboDefault(); }
    }
    // Combines both this file's own startup actions -- QML only permits one
    // Component.onCompleted per object, so the F1 initial-focus claim
    // (see the header note near `onVisibleChanged` above, which covers the
    // dialog becoming visible LATER; this covers it already being visible
    // on the very first frame) lives here alongside the pre-existing combo
    // default sync rather than as a second handler.
    Component.onCompleted: {
        root._syncComboDefault();
        if (root.visible) userField.forceFocus();
    }

    function _resolveEntry() {
        var list = (!!root.sessions && root.sessions.list) || [];
        if (combo.currentIndex >= 0 && combo.currentIndex < list.length)
            return list[combo.currentIndex];
        var idx = root._defaultSessionIndex();
        return idx >= 0 ? list[idx] : null;
    }

    function _pickerEnabled() {
        var cfgSessions = root.settings && root.settings.config && root.settings.config.sessions;
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

    // rememberLastUser is a COSMETIC key (SettingsMerge.js's COSMETIC table),
    // absent-or-true by default (the Nix-rendered defaults.json always sets
    // it explicitly, but a hand-built Settings.config in a test might not),
    // so the check is `!== false`, not a bare truthiness read on a possibly
    // undefined value.
    readonly property bool _rememberLastUser:
        !root.settings || !root.settings.config || root.settings.config.rememberLastUser !== false

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
        //
        // rememberLastUser = false skips this write entirely -- not just
        // the prefill below -- so a user who opted out never has their name
        // land on disk from a successful login, no matter what a previous
        // (remembering) login already left there.
        if (root._rememberLastUser && root.greeterState) root.greeterState.lastUser = root.session.user;
        if (root.greeterState) {
            root.greeterState.lastSession = entry.name;
            root.greeterState.save();
        }
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
    // Final micro-fix, Item 2: see XpTextField.qml's own comment on why
    // this counts calls rather than reading activeFocus directly.
    readonly property alias testUserFieldForceFocusCalls: userField._forceFocusCalls
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
    // Sets secretField's text directly. Only exists so a test can put
    // something in the field to then prove _cancel() actually clears it --
    // secretField.text has no declarative binding of its own to break
    // (unlike userField.text, bound to GreeterState.lastUser, which a test
    // seeds through that binding instead so there is nothing for this
    // function to need to do for that field).
    function testSetSecretText(text) { secretField.text = text; }

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
                // Label beside the box in a fixed right-aligned column,
                // which is how the real dialog lays this out -- see
                // XpTextField's own note on why stacking reads wrong.
                labelWidth: root.theme.labelColumnWidth
                // Skips the prefill outright when rememberLastUser is
                // false, independent of whatever GreeterState.lastUser
                // still holds on disk (root._rememberLastUser, defined
                // below near _launchSelected() which is the other half of
                // this same setting).
                text: (root._rememberLastUser && !!root.greeterState) ? root.greeterState.lastUser : ""
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
                labelWidth: root.theme.labelColumnWidth
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
            // Same label column as the two field rows above it, so the three
            // rows line up down a single edge once Options is expanded --
            // which is the point of a label column, and does not happen if
            // this one row keeps its own stacked layout.
            Item {
                id: sessionRow
                width: parent.width
                visible: root.optionsExpanded
                height: visible ? root.theme.controlHeight : 0

                Text {
                    id: sessionLabel
                    text: "Log on to:"
                    width: root.theme.labelColumnWidth
                    horizontalAlignment: Text.AlignRight
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.theme.infoText
                    font.family: root.theme.uiBold
                    font.pixelSize: root.theme.uiSize
                    textFormat: Text.PlainText
                }
                Widgets.XpComboBox {
                    id: combo
                    theme: root.theme
                    anchors.left: sessionLabel.right
                    anchors.leftMargin: root.theme.rowSpacing
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
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
                // Indented to the field column, not to the dialog edge, so
                // status and prompt text share the left edge the boxes
                // start at rather than starting under the labels.
                x: root.theme.labelColumnWidth + root.theme.rowSpacing
                width: parent.width - x
                text: root.statusLineText
                textFormat: Text.PlainText
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
        bannerTitle: (!!root.settings && root.settings.config.branding && root.settings.config.branding.title)
            || "Log On to Windows"
        bannerSubtitle: (!!root.settings && root.settings.config.branding && root.settings.config.branding.subtitle) || ""
        // The brand panel. Every string is cosmetic, user-tier, and blank
        // unless configured -- see XpBanner's own note on why this skin
        // ships no default copyright or vendor line of its own. The panel
        // itself still appears (flag and blue field) when they are blank,
        // because it is structural chrome rather than a caption.
        bannerBrand: true
        bannerCopyright: root._brand("copyright")
        bannerEdition: root._brand("edition")
        bannerWordmark: root._brand("wordmark")
        bannerWordmarkAccent: root._brand("wordmarkAccent")
        bannerVendor: root._brand("vendor")
        // Nix-only: SettingsMerge.js does not copy branding.image out of
        // the user tier, so this can only ever be the store path the module
        // rendered into defaults.json.
        bannerImage: root._brand("image")
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
        visible: !!root.capsLock && root.capsLock.on
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
