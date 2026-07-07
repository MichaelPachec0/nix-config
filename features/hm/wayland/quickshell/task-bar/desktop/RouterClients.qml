import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../lib/routerfmt.js" as RouterFmt

// Compact connected-clients list for the router popup. The rows live in a
// height-capped ListView so a busy network scrolls instead of stretching the
// popup; the "Clients (N)" header stays pinned above. When the list overflows,
// each row reserves a right-hand gutter so the scrollbar is the rightmost item
// and never overlaps the throughput text. Mirrors NetworkPopup.qml.
ColumnLayout {
    id: root
    required property QtObject theme
    property var clients: []
    property int maxHeight: 112   // ~7 rows before the list starts scrolling
    spacing: 2

    Text {
        text: "Clients (" + root.clients.length + ")"
        font.family: root.theme.iconFont
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.theme.textSecondary
    }
    ListView {
        id: clientList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, root.maxHeight)
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.clients

        readonly property bool overflowing: contentHeight > height
        // Space the rows yield on the right when the scrollbar shows: bar (6) + gap (4).
        readonly property int scrollGutter: 10

        delegate: RowLayout {
            required property var modelData
            width: clientList.width - (clientList.overflowing ? clientList.scrollGutter : 0)
            spacing: 8
            Text {
                text: modelData.name || modelData.ip || "?"
                font.family: root.theme.iconFont
                font.pixelSize: 10
                color: root.theme.textPrimary
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            Text {
                text: modelData.ip ? "." + String(modelData.ip).split(".").pop() : ""
                font.family: root.theme.iconFont
                font.pixelSize: 10
                color: root.theme.textSecondary
                Layout.preferredWidth: 40
            }
            Item { Layout.fillWidth: true }
            Text {
                text: (modelData.rx || modelData.tx)
                    ? ("dn " + RouterFmt.fmtRate(modelData.rx) + "  up " + RouterFmt.fmtRate(modelData.tx))
                    : "idle"
                font.family: root.theme.iconFont
                font.pixelSize: 10
                color: root.theme.textSecondary
            }
        }

        ScrollBar.vertical: ScrollBar {
            id: vbar
            policy: clientList.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            width: 6
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: vbar.pressed ? root.theme.accent : root.theme.bgItemHover
                opacity: vbar.active ? 1.0 : 0.85
            }
            background: Rectangle {
                color: "transparent"
            }
        }
    }
}
