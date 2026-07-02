import QtQuick
import QtQuick.Layouts
import "../lib/routerfmt.js" as RouterFmt

// Compact connected-clients list for the router popup.
ColumnLayout {
    id: root
    required property QtObject theme
    property var clients: []
    spacing: 2

    Text {
        text: "Clients (" + root.clients.length + ")"
        font.family: root.theme.textFont
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.theme.textSecondary
    }
    Repeater {
        model: root.clients
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: modelData.name || modelData.ip || "?"
                font.family: root.theme.textFont
                font.pixelSize: 10
                color: root.theme.textPrimary
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            Text {
                text: modelData.ip ? "." + String(modelData.ip).split(".").pop() : ""
                font.family: root.theme.textFont
                font.pixelSize: 10
                color: root.theme.textSecondary
                Layout.preferredWidth: 40
            }
            Item { Layout.fillWidth: true }
            Text {
                text: (modelData.rx || modelData.tx)
                    ? ("dn " + RouterFmt.fmtRate(modelData.rx) + "  up " + RouterFmt.fmtRate(modelData.tx))
                    : "idle"
                font.family: root.theme.textFont
                font.pixelSize: 10
                color: root.theme.textSecondary
            }
        }
    }
}
