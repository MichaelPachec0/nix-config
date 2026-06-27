import QtQuick
import QtQuick.Layouts
import Quickshell

// Hover tooltip over the bar widget: a summary of the connected device(s), or
// an idle/off message. Mirrors WifiInfoPopup -- grabFocus:false so it never
// steals focus.
PopupWindow {
    id: tip

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var bt

    implicitWidth: 220
    implicitHeight: col.implicitHeight + 20
    color: "transparent"
    visible: false
    grabFocus: false

    anchor.window: tip.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    function showAt(px) {
        tip.anchor.rect.x = px;
        tip.anchor.rect.y = tip.barWindow.height + 4;
        tip.anchor.rect.width = 0;
        tip.anchor.rect.height = 0;
        tip.visible = true;
    }
    function show() {
        if (tip.visible)
            return;
        tip.showAt(tip.anchorItem.mapToItem(null, 0, 0).x);
    }
    function hide() {
        tip.visible = false;
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 11
        color: tip.theme.bgCard
        border.width: 1
        border.color: tip.theme.border

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 6

            Text {
                Layout.fillWidth: true
                visible: !tip.bt.available || !tip.bt.enabled
                text: !tip.bt.available ? "No Bluetooth adapter" : "Bluetooth off"
                color: tip.theme.textSecondary
                font.family: tip.theme.textFont
                font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                visible: tip.bt.enabled && tip.bt.connectedDevices.length === 0
                text: "No device connected"
                color: tip.theme.textSecondary
                font.family: tip.theme.textFont
                font.pixelSize: 12
            }
            Repeater {
                model: tip.bt.enabled ? tip.bt.connectedDevices : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: tip.bt.typeGlyph(modelData.icon)
                        color: tip.theme.accent
                        font.family: tip.theme.iconFont
                        font.pixelSize: 15
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.deviceName || modelData.name || modelData.address
                        color: tip.theme.textPrimary
                        font.family: tip.theme.textFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: modelData.batteryAvailable
                        text: Math.round(modelData.battery * 100) + "%"
                        color: tip.theme.textSecondary
                        font.family: tip.theme.textFont
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
