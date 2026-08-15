import QtQuick

// A Luna text box, with its label either beside it or above it.
//
// Two fidelity notes worth keeping, because both were wrong before and both
// are the kind of thing that reads as "close but not XP":
//
// 1. Luna draws a field as a SINGLE flat slate-blue hairline. The sunken
//    two-tone bevel -- dark on top and left, light on bottom and right -- is
//    Windows Classic/9x, not Luna. Drawing both at once (a hairline plus an
//    inner etched line, which is what this widget used to do) reads as a
//    muddy double border.
//
// 2. On the Log On to Windows dialog specifically, the label sits to the
//    LEFT of its box on the same row, right-aligned in a fixed column --
//    not stacked above it. Stacking is what a modern form does, and it is
//    enough on its own to make the dialog look like a reproduction from
//    memory. `labelWidth` selects between the two: > 0 puts the label in a
//    column of that width beside the field, 0 keeps the stacked layout for
//    callers (the shutdown dialog, the gallery) that want it.
Item {
    id: root
    required property var theme
    property string label: ""
    property string text: ""
    property bool echo: false
    property bool enabled: true
    property int labelWidth: 0
    signal accepted()

    readonly property bool inlineLabel: root.labelWidth > 0 && root.label.length > 0

    // Exposed for headless testing only: lets a caller confirm `echo`
    // actually drove the TextInput's echoMode without duplicating the
    // TextInput.Password/Normal mapping outside this file.
    readonly property int echoMode: input.echoMode

    // Exposed for headless testing only: input.activeFocus itself is not
    // observable under offscreen QPA (confirmed empirically -- forceActive
    // Focus() never actually flips it without a real window, since a bare
    // ShellRoot with no PanelWindow establishes no focus scope at all), so
    // this counts CALLS to forceFocus() instead, as the only observable
    // proxy this harness has for "a focus claim was made." Proves the
    // CODE PATH fired; whether the OS-level focus actually lands still
    // needs the interactive pass.
    property int _forceFocusCalls: 0
    readonly property alias testForceFocusCalls: root._forceFocusCalls

    implicitWidth: 200
    implicitHeight: root.inlineLabel
        ? theme.controlHeight
        : (labelText.visible ? labelText.implicitHeight + theme.rowSpacing / 2 : 0) + theme.controlHeight
    width: implicitWidth
    height: implicitHeight
    // Dims the whole field -- label and box together -- and is externally
    // observable on the widget itself, same reasoning as XpButton.
    opacity: root.enabled ? 1.0 : 0.75

    Text {
        id: labelText
        visible: root.label.length > 0
        text: root.label
        textFormat: Text.PlainText
        color: theme.infoText
        font.family: theme.uiBold
        font.pixelSize: theme.uiSize
        // XP does not bold these labels; the previous version did, which
        // made the dialog look heavier than the real one at every size.
        font.bold: false

        // Inline: right-aligned in its own column, vertically centred on the
        // box. Stacked: flush left, above the box.
        width: root.inlineLabel ? root.labelWidth : implicitWidth
        horizontalAlignment: root.inlineLabel ? Text.AlignRight : Text.AlignLeft
        anchors.left: parent.left
        anchors.top: root.inlineLabel ? undefined : parent.top
        anchors.verticalCenter: root.inlineLabel ? parent.verticalCenter : undefined
    }

    Rectangle {
        id: field
        anchors.left: root.inlineLabel ? labelText.right : parent.left
        anchors.leftMargin: root.inlineLabel ? theme.rowSpacing : 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: theme.controlHeight
        color: root.enabled ? theme.fieldBg : theme.fieldDisabled
        border.width: 1
        border.color: theme.fieldBorder

        // theme.focusRing made visible: a pure overlay drawn INSIDE the
        // box rather than outside it, so it cannot overlap the label column
        // beside it or perturb this widget's implicit size.
        Rectangle {
            id: focusRing
            visible: input.activeFocus
            anchors.fill: parent
            anchors.margins: 1
            color: "transparent"
            border.width: 1
            border.color: theme.focusRing
            opacity: 0.35
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            verticalAlignment: TextInput.AlignVCenter
            echoMode: root.echo ? TextInput.Password : TextInput.Normal
            text: root.text
            color: root.enabled ? theme.fieldText : theme.fieldDisabledText
            font.family: theme.ui
            font.pixelSize: theme.uiSize
            enabled: root.enabled
            selectByMouse: true
            // XP.css _forms.scss: `input::selection { background:
            // var(--dialog-blue); color: white }`. Without these the
            // selection falls back to whatever Qt's default palette says,
            // which on this greeter is not XP's blue.
            selectionColor: theme.selectionBg
            selectedTextColor: theme.selectionText
            clip: true
            onTextChanged: if (root.text !== text) root.text = text
            onAccepted: root.accepted()
        }
    }

    // Keep the field's TextInput in sync when `text` is set from outside
    // (e.g. cleared after a failed attempt). Guarded both directions so this
    // is an imperative sync, not a declarative binding cycle -- it never
    // prints a "Binding loop detected" warning.
    onTextChanged: if (input.text !== root.text) input.text = root.text

    function forceFocus() {
        root._forceFocusCalls++;
        input.forceActiveFocus();
    }
}
