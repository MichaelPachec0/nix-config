import QtQuick
import "../lib" as Lib
import QtQuick.Layouts
import "../lib/routerfmt.js" as RouterFmt

// Bar item: cellular signal bars (colored by RSRP) + network-type tag (tinted by
// uplink health) + battery, or a dimmed "not connected" chip when off the E5800.
// Hover opens RouterPopup.
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
    // Router glyph tint: working uplink -> green, reachable but no uplink -> red.
    function connColor() {
        if (!root.svc.reachable)
            return root.theme.textSecondary;
        return root.svc.uplink.online ? root.theme.accentGreen : root.theme.accentRed;
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
        // Network-type tag, tinted by uplink health (green online / red no uplink).
        Lib.BarText {
            visible: root.svc.reachable && !root.svc.authError && (root.svc.cellular.supported !== false)
            text: root.svc.cellular.gen || "?"
            font.family: root.theme.iconFont
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: root.connColor()
        }
        // Carrier-aggregation count (e.g. "3CA"), from AT+QCAINFO. Shown whenever
        // at least the primary carrier is up -- fixed width, so a count change
        // (3CA <-> 1CA) never reflows the taskbar.
        Lib.BarText {
            property var ca: root.svc.cellular.ca
            visible: root.svc.reachable && !root.svc.authError && ca && ca.count >= 1
            text: ca ? (ca.count + "CA") : ""
            font.family: root.theme.iconFont
            font.pixelSize: 11
            color: root.theme.textSecondary
        }
        // Re-auth warning glyph: reachable but SSH key rejected (router factory-reset).
        // The popup carries the "re-add the key" explanation.
        Lib.BarText {
            visible: root.svc.reachable && root.svc.authError
            text: String.fromCharCode(0xF071) // fa exclamation-triangle
            font.family: root.theme.faFont
            font.pixelSize: 13
            color: root.theme.accentRed
        }
        // Router battery percent (JetBrainsMono, like the other bar labels).
        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.svc.reachable
            text: root.svc.battery.percent !== undefined ? root.svc.battery.percent + "%" : "--"
            font.family: root.theme.iconFont
            font.pixelSize: 11
            color: root.battColor()
        }
        // Dimmed "not connected" chip.
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.svc.reachable
            opacity: 0.4
            spacing: 3
            Lib.BarText {
                text: String.fromCharCode(0xF519) // fa network-wired (router)
                font.family: root.theme.faFont
                font.pixelSize: 13
                color: root.theme.textSecondary
            }
            Lib.BarText {
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
