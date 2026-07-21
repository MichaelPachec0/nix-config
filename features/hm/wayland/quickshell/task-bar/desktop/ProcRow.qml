import QtQuick
import QtQuick.Layouts
import Quickshell

// One process row for SysProcSection: a name (elided) + a right-aligned metric,
// with a hover highlight and the shared gestures -- left-click arms then kills
// (via the section's armOrKill), Shift+click SIGKILLs immediately, middle-click
// copies "pid name" to the clipboard. The arm state is owned by the section
// (armedPid, keyed by pid) so it survives the per-poll model churn; this row
// only reflects it. `valueText`/`valueWidth` differ between the memory and CPU
// columns; everything else is identical, which is why this was two copies.
Item {
    id: rowRoot

    required property QtObject theme
    required property var modelData     // { pid, name, ... } injected by the Repeater
    required property int armedPid      // section arm state
    required property string valueText  // metric shown when not armed
    required property real valueWidth   // reserved numeric-column width
    signal armOrKill(int pid)

    readonly property bool armed: rowRoot.modelData.pid === rowRoot.armedPid

    Layout.fillWidth: true
    implicitHeight: procRow.implicitHeight

    Rectangle {
        anchors.fill: parent
        color: procArea.containsMouse ? rowRoot.theme.bgItemHover : "transparent"
        radius: 2
    }

    RowLayout {
        id: procRow
        anchors { left: parent.left; right: parent.right }
        Text {
            text: rowRoot.modelData.name
            font.family: rowRoot.theme.iconFont; font.pixelSize: 10
            color: rowRoot.theme.textPrimary
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: rowRoot.armed ? "end?" : rowRoot.valueText
            font.family: rowRoot.theme.iconFont; font.pixelSize: 10
            color: rowRoot.armed ? rowRoot.theme.accentRed : rowRoot.theme.textSecondary
            horizontalAlignment: Text.AlignRight
            Layout.minimumWidth: rowRoot.valueWidth
            Layout.preferredWidth: rowRoot.valueWidth
        }
    }

    MouseArea {
        id: procArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function (m) {
            if (m.button === Qt.MiddleButton) {
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/clip-copy.sh",
                    rowRoot.modelData.pid + " " + rowRoot.modelData.name]);
                return;
            }
            if (m.modifiers & Qt.ShiftModifier) {
                Quickshell.execDetached(["kill", "-KILL", String(rowRoot.modelData.pid)]);
                return;
            }
            rowRoot.armOrKill(rowRoot.modelData.pid);
        }
    }
}
