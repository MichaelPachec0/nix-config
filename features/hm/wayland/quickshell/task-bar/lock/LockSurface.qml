// features/hm/wayland/quickshell/task-bar/lock/LockSurface.qml
// Per-output lock UI: backdrop + clock + password dots + failure feedback.
// Non-security presentation. All surfaces share the same `context`, so typing /
// feedback is mirrored across outputs.
import QtQuick

Item {
    id: root
    required property var context
    property string backdropSource: ""

    LockBackdrop {
        anchors.fill: parent
        source: root.backdropSource
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 28

        // Clock
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ebdbb2"
            font.pixelSize: 72
            font.bold: true
            text: Qt.formatDateTime(clockTick.now, "HH:mm")
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#a89984"
            font.pixelSize: 22
            text: Qt.formatDateTime(clockTick.now, "dddd, MMMM d")
        }

        // Password dots
        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320; height: 52; radius: 26
            color: "#282828"; opacity: 0.85
            border.width: 2
            border.color: root.context.showFailure ? "#fb4934" : "#504945"

            Row {
                anchors.centerIn: parent
                spacing: 10
                Repeater {
                    model: root.context.currentText.length
                    Rectangle { width: 12; height: 12; radius: 6; color: "#ebdbb2" }
                }
            }

            // Hidden real input drives context.currentText.
            TextInput {
                id: input
                anchors.fill: parent
                opacity: 0
                focus: true
                echoMode: TextInput.Password
                text: root.context.currentText
                onTextChanged: root.context.currentText = text
                onAccepted: root.context.tryUnlock()
                Component.onCompleted: forceActiveFocus()
            }

            // Shake on failure.
            SequentialAnimation {
                id: shake
                loops: 1
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 12; duration: 40 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -12; duration: 80 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
            }
        }

    }

    // Message line (PAM prompts / "Incorrect password"). Positioned OUTSIDE the
    // centered Column and anchored below it, so toggling it never reflows the
    // clock/field -- they stay put whether or not a message is showing.
    Text {
        anchors.horizontalCenter: column.horizontalCenter
        anchors.top: column.bottom
        anchors.topMargin: 12
        visible: root.context.showFailure || root.context.statusMessage.length > 0
        color: (root.context.showFailure || root.context.statusIsError) ? "#fb4934" : "#a89984"
        font.pixelSize: 16
        text: root.context.showFailure
            ? ("Incorrect password" + (root.context.failCount > 1 ? " (" + root.context.failCount + ")" : ""))
            : root.context.statusMessage
    }

    // Re-focus the hidden input whenever this surface (re)appears.
    onVisibleChanged: if (visible) input.forceActiveFocus()

    Connections {
        target: root.context
        function onFailed() { shake.restart(); }
    }

    // 1s clock tick.
    QtObject { id: clockTick; property var now: new Date() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: clockTick.now = new Date(); }
}
