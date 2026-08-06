import QtQuick

Item {
    id: root
    required property var theme
    property string label: ""
    property string text: ""
    property bool echo: false
    property bool enabled: true
    signal accepted()

    // Exposed for headless testing only: lets a caller confirm `echo`
    // actually drove the TextInput's echoMode without duplicating the
    // TextInput.Password/Normal mapping outside this file.
    readonly property int echoMode: input.echoMode

    implicitWidth: Math.max(160, column.implicitWidth)
    implicitHeight: column.implicitHeight
    width: implicitWidth
    height: implicitHeight
    // Dims the whole field -- label and box together -- and is externally
    // observable on the widget itself, same reasoning as XpButton.
    opacity: root.enabled ? 1.0 : 0.75

    Column {
        id: column
        anchors.fill: parent
        spacing: theme.rowSpacing / 2

        Text {
            id: labelText
            visible: root.label.length > 0
            text: root.label
            color: theme.infoText
            font.family: theme.uiBold
            font.bold: true
            font.pixelSize: theme.uiSize
        }

        Rectangle {
            id: field
            width: column.width
            height: theme.controlHeight
            color: root.enabled ? theme.fieldBg : theme.fieldDisabled
            border.width: 1
            border.color: theme.fieldBorder

            // Sunken 2px inset: a one-pixel etched line just inside the
            // outer border, the classic Windows "field cut into the face"
            // look, built from theme colors rather than a bitmap.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                color: "transparent"
                border.width: 1
                border.color: theme.faceShadow
            }

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                verticalAlignment: TextInput.AlignVCenter
                echoMode: root.echo ? TextInput.Password : TextInput.Normal
                text: root.text
                color: theme.fieldText
                font.family: theme.ui
                font.pixelSize: theme.uiSize
                enabled: root.enabled
                selectByMouse: true
                clip: true
                onTextChanged: if (root.text !== text) root.text = text
                onAccepted: root.accepted()
            }
        }
    }

    // Keep the field's TextInput in sync when `text` is set from outside
    // (e.g. cleared after a failed attempt). Guarded both directions so this
    // is an imperative sync, not a declarative binding cycle -- it never
    // prints a "Binding loop detected" warning.
    onTextChanged: if (input.text !== root.text) input.text = root.text

    function forceFocus() { input.forceActiveFocus(); }
}
