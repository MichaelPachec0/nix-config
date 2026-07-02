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

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 6

        // Signal bars (5 segments); fill + color from RSRP band.
        Row {
            spacing: 1
            visible: root.svc.reachable && (root.svc.cellular.supported !== false)
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
        Text {
            visible: root.svc.reachable && (root.svc.cellular.supported !== false)
            text: root.svc.cellular.gen || "?"
            font.family: root.theme.textFont
            font.pixelSize: 9
            font.weight: Font.DemiBold
            color: root.theme.textSecondary
        }
        // Battery pill (router's -- glyph distinguishes from laptop battery).
        Text {
            visible: root.svc.reachable
            text: String.fromCharCode(0xF519) + " " + (root.svc.battery.percent !== undefined
                  ? root.svc.battery.percent + "%" : "--")
            font.family: root.theme.faFont
            font.pixelSize: 11
            color: root.svc.battery.charging ? root.theme.accentGreen
                 : (root.svc.battery.percent !== undefined && root.svc.battery.percent < 20
                    ? root.theme.accentRed : root.theme.textSecondary)
        }
        // Dimmed "not connected" chip.
        Text {
            visible: !root.svc.reachable
            text: String.fromCharCode(0xF519) + " off"
            font.family: root.theme.faFont
            font.pixelSize: 11
            opacity: 0.4
            color: root.theme.textSecondary
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
