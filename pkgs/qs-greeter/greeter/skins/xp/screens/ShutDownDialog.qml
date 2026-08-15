import QtQuick
import "../widgets" as Widgets

// The XP "Shut Down Windows" modal. Skin.qml owns `shutDownVisible` and is
// the only thing that shows or hides this screen -- both LogonDialog.qml
// and SkinFatal.qml can ask for it (their own `shutDownRequested()` signal)
// but neither one talks to this file directly, and this file does not
// import Session/Sessions/Settings/GreeterState itself. It only ever knows
// `theme`, and it only ever produces one of three fixed strings.
//
// SECURITY BOUNDARY: this is how an unauthenticated person at the physical
// console reboots or powers off the machine. That is intentional -- every
// greeter offers this before login -- but it means the only actions
// reachable from here are the three named below, mapped to fixed argv two
// layers up in shell.qml's power(). `_actions` is a literal, closed array:
// nothing computes it, nothing reads an action name from Settings or any
// file, and `_ok()` below only ever emits one of its three literal
// `action` fields verbatim -- never a string built from user input or
// interpolated in any way. If a future edit finds itself constructing a
// command line, or taking an action name from anywhere but this array,
// that is this boundary being crossed; stop.
Item {
    id: root
    required property var theme

    // Fires with exactly "suspend", "poweroff", or "reboot" -- see the
    // SECURITY BOUNDARY note above. Skin.qml forwards this straight into
    // its own pre-existing `requestPower(action)` signal, the same one
    // shell.qml already wires to power() -- this file does not duplicate
    // that mapping, it only ever selects which of the three fixed strings
    // to hand up.
    signal requestPower(string action)
    // Cancel, or Escape: closes the modal, asks for nothing. Kept
    // deliberately separate from requestPower so there is no way for a
    // "close this" path to also, even accidentally, fire a power action.
    signal cancelled()

    // Literal and closed: exactly these three rows, in this order, each
    // with its own exact description (verbatim strings -- asserted by the
    // headless suite) and its own fixed action. Nothing extends this list
    // at runtime; nothing outside this file can reach into it.
    readonly property var _actions: [
        { label: "Stand By", action: "suspend",
          description: "Maintains your session, keeping the computer running on low power with data still in memory." },
        { label: "Turn Off", action: "poweroff",
          description: "Ends your session and turns off the computer." },
        { label: "Restart", action: "reboot",
          description: "Ends your session and restarts the computer." }
    ]

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // Bound to root.visible, not a bare `true`: this Item is constructed
    // once, eagerly, by Skin.qml and only ever toggled via `visible:
    // root.shutDownVisible` at that call site -- a static `focus: true`
    // here would request keyboard focus the instant the skin loads, before
    // the user ever asked to see this modal, and could steal it away from
    // LogonDialog.qml's own fields. Tying it to `visible` means the
    // request (and the focus itself) exists only while the modal is
    // actually up, and is relinquished the instant it closes.
    focus: root.visible
    Keys.onEscapePressed: root._cancel()
    Keys.onReturnPressed: root._ok()

    // Every time the modal is (re)shown, start over: Stand By selected,
    // help balloon closed. Opening it fresh should never silently carry
    // over whatever a previous visit left selected.
    onVisibleChanged: if (root.visible) {
        combo.currentIndex = 0;
        helpBalloon.visible = false;
    }

    function _ok() {
        var idx = combo.currentIndex;
        if (idx < 0 || idx >= root._actions.length) return;
        root.requestPower(root._actions[idx].action);
    }

    function _cancel() {
        root.cancelled();
    }

    function _help() {
        helpBalloon.visible = true;
    }

    // --- exposed for headless testing only (same convention as
    // LogonDialog.qml's testXxx aliases: a child's own property, aliased
    // out under a name that says what it is for). _ok()/_cancel()/_help()
    // above are called directly by tests, the same way LogonDialog.qml's
    // suite calls dlg._cancel() directly -- there is no separate
    // test-only wrapper for those. ---
    readonly property alias testActionLabels: combo.model
    readonly property alias testCurrentIndex: combo.currentIndex
    readonly property alias testDescriptionText: descriptionText.text
    readonly property alias testHelpBalloonVisible: helpBalloon.visible
    function testSelectIndex(idx) { combo.currentIndex = idx; }

    Item {
        id: content
        implicitWidth: rows.implicitWidth
        implicitHeight: rows.implicitHeight

        Column {
            id: rows
            width: parent.width
            spacing: root.theme.rowSpacing

            Text {
                width: parent.width
                text: "What do you want the computer to do?"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.theme.infoText
                font.family: root.theme.ui
                font.pixelSize: root.theme.uiSize
            }

            Widgets.XpComboBox {
                id: combo
                theme: root.theme
                model: root._actions.map(function (a) { return a.label; })
                currentIndex: 0
            }

            // The one row that changes with the selection -- everything
            // else in this dialog is fixed once it opens.
            Text {
                id: descriptionText
                width: parent.width
                text: (combo.currentIndex >= 0 && combo.currentIndex < root._actions.length)
                    ? root._actions[combo.currentIndex].description : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.theme.infoText
                font.family: root.theme.ui
                font.pixelSize: root.theme.uiSize
            }
        }
    }

    Widgets.XpDialog {
        id: dialog
        theme: root.theme
        bannerTitle: "Shut Down Windows"
        bannerSubtitle: ""
        contentItem: content
        buttons: [
            { text: "OK", isDefault: true,
              onClicked: function () { root._ok(); } },
            { text: "Cancel",
              onClicked: function () { root._cancel(); } },
            { text: "Help",
              onClicked: function () { root._help(); } }
        ]
    }

    // Explains the three options rather than Help being dead. Targets the
    // dialog itself (not the Help button specifically): XpDialog builds
    // its button row from a plain data array through an internal Repeater
    // (see XpDialog.qml), so there is no Item id for "the Help button" to
    // anchor to from outside it -- the same reason widgets-gallery.qml has
    // to walk XpMessageBox's child tree to find its OK button rather than
    // reference it by id.
    Widgets.XpBalloon {
        id: helpBalloon
        theme: root.theme
        visible: false
        target: dialog
        text: "Stand By keeps your session open, running on low power with your work still in memory. "
            + "Turn Off ends your session and powers the computer off. "
            + "Restart ends your session and starts the computer again."
    }
}
