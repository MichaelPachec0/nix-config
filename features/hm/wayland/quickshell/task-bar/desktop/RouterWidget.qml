import QtQuick
import QtQuick.Layouts
import "../lib/routerfmt.js" as RouterFmt

// Bar item: cellular signal (colored by RSRP) + gen tag + router battery, or a
// dimmed "not connected" chip when off the E5800. Hover opens RouterPopup.
Item {
    id: root
    required property QtObject theme
    required property var svc
    required property var barWindow

    implicitWidth: rowLayout.implicitWidth + 12
    implicitHeight: parent ? parent.height : 22

    function qColor(q) {
        return q === "good" ? root.theme.accentGreen
             : q === "fair" ? root.theme.accentYellow
             : root.theme.accentRed;
    }
    function battColor() {
        return root.svc.battery.charging ? root.theme.accentGreen
             : (root.svc.battery.percent !== undefined && root.svc.battery.percent < 20
                ? root.theme.accentRed : root.theme.textSecondary);
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 6

        // Signal bars (5 segments); fill + color from RSRP band.
        Row {
            spacing: 1
            visible: root.svc.reachable && !root.svc.authError && (root.svc.cellular.supported !== false)
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    width: 3
                    height: 4 + index * 2
                    anchors.bottom: parent ? parent.bottom : undefined
                    radius: 1
                    property int fill: RouterFmt.barFill(root.svc.cellular.strength)
                    color: index < fill
                        ? root.qColor(RouterFmt.quality("rsrp", root.svc.cellular.rsrp))
                        : Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g,
                                  root.theme.textSecondary.b, 0.3)
                }
            }
        }
        // Network-type tag (JetBrainsMono, like the other bar labels).
        Text {
            visible: root.svc.reachable && !root.svc.authError && (root.svc.cellular.supported !== false)
            text: root.svc.cellular.gen || "?"
            font.family: root.theme.iconFont
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: root.theme.textSecondary
        }
        // Re-auth warning glyph: reachable but SSH key rejected (router factory-reset).
        // The popup carries the "re-add the key" explanation.
        Text {
            visible: root.svc.reachable && root.svc.authError
            text: String.fromCharCode(0xF071) // fa exclamation-triangle
            font.family: root.theme.faFont
            font.pixelSize: 13
            color: root.theme.accentRed
        }
        // Battery pill (router's -- faFont glyph distinguishes from the laptop
        // battery; the percent is JetBrainsMono like the other bar labels).
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: root.svc.reachable
            spacing: 3
            Text {
                text: String.fromCharCode(0xF519) // fa network-wired (router)
                font.family: root.theme.faFont
                font.pixelSize: 13
                color: root.battColor()
            }
            Text {
                text: root.svc.battery.percent !== undefined ? root.svc.battery.percent + "%" : "--"
                font.family: root.theme.iconFont
                font.pixelSize: 11
                color: root.battColor()
            }
        }
        // Dimmed "not connected" chip.
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.svc.reachable
            opacity: 0.4
            spacing: 3
            Text {
                text: String.fromCharCode(0xF519) // fa network-wired (router)
                font.family: root.theme.faFont
                font.pixelSize: 13
                color: root.theme.textSecondary
            }
            Text {
                text: "off"
                font.family: root.theme.iconFont
                font.pixelSize: 11
                color: root.theme.textSecondary
            }
        }
    }

    RouterPopup {
        id: pop
        theme: root.theme
        svc: root.svc
        barWindow: root.barWindow
        anchorItem: root
    }
    HoverHandler {
        id: hov
        onHoveredChanged: hov.hovered ? pop.show() : hideTimer.restart()
    }
    Timer {
        id: hideTimer
        interval: 250
        onTriggered: if (!hov.hovered && !pop.contentHovered) pop.hide()
    }
}
