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
        return q === "excellent" ? root.theme.accentGreen
             : q === "good" ? root.theme.accentBlue
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
                    id: bar
                    required property int index
                    width: 3
                    height: 4 + index * 2
                    anchors.bottom: parent ? parent.bottom : undefined
                    radius: 1
                    property int fill: RouterFmt.barFill(root.svc.cellular.strength)
                    // Empty segments: a solid dim grey (the pill's ring color), NOT a
                    // translucent one. These cast their own drop below, and at low alpha
                    // that dark copy shows through and the bar reads as sitting *below*
                    // its own shadow. Full opacity keeps the empty track on the same
                    // depth plane as the colored bars; the dim hue -- not transparency --
                    // is what reads as "off".
                    color: index < fill
                        ? root.qColor(RouterFmt.quality("rsrp", root.svc.cellular.rsrp))
                        : root.theme.border

                    // Match Lib.BarText's raised look. These bars are Rectangles, not
                    // glyphs, so they get none of Text.Raised or BarText's lift -- and
                    // since Pill's frosted shadow pass now covers only the capsule (not
                    // its content), nothing else casts for them either. Same technique as
                    // BarText: a copy at negative z, which draws behind the parent's own
                    // content, offset by the shared BarStyle depth.
                    // Lib.BarStyle, not a bare BarStyle: the singleton lives in ../lib,
                    // so outside that directory it is only reachable through the import
                    // alias. A bare reference silently resolves to nothing and throws
                    // "BarStyle is not defined" per delegate, per frame.
                    Repeater {
                        model: Lib.BarStyle.glyphLifted ? Lib.BarStyle.glyphLiftSteps : 0
                        delegate: Rectangle {
                            required property int index
                            // index 0 = deepest, created first so nearer steps stack on it.
                            readonly property int step: Lib.BarStyle.glyphLiftSteps - index
                            z: -1
                            x: Math.round(step * Lib.BarStyle.glyphLiftX / Lib.BarStyle.glyphLiftSteps)
                            y: Math.round(step * Lib.BarStyle.glyphLiftY / Lib.BarStyle.glyphLiftSteps)
                            width: bar.width
                            height: bar.height
                            radius: bar.radius
                            color: Qt.rgba(0, 0, 0, Lib.BarStyle.glyphLiftAlpha)

                            // Halo on the deepest step only, matching BarText. A solid
                            // shape needs no eight-way spread -- one inflated copy already
                            // has a clean symmetric edge -- but that means it gets the
                            // accumulated alpha in ONE draw where the text gets it from
                            // eight overlapping ones, hence the 2x.
                            Rectangle {
                                visible: index === 0 && Lib.BarStyle.glyphGlowEnabled && Lib.BarStyle.glyphGlowAlpha > 0
                                z: -1
                                x: -Lib.BarStyle.glyphGlowSpread + Lib.BarStyle.glyphGlowOffsetX
                                y: -Lib.BarStyle.glyphGlowSpread + Lib.BarStyle.glyphGlowOffsetY
                                width: parent.width + 2 * Lib.BarStyle.glyphGlowSpread
                                height: parent.height + 2 * Lib.BarStyle.glyphGlowSpread
                                radius: parent.radius + Lib.BarStyle.glyphGlowSpread
                                color: Qt.rgba(Lib.BarStyle.glyphGlowColor.r, Lib.BarStyle.glyphGlowColor.g, Lib.BarStyle.glyphGlowColor.b, Math.min(1, Lib.BarStyle.glyphGlowAlpha * 2))
                            }
                        }
                    }
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
            color: root.theme.textPrimary
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
                color: root.theme.textPrimary
            }
            Lib.BarText {
                text: "off"
                font.family: root.theme.iconFont
                font.pixelSize: 11
                color: root.theme.textPrimary
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
    }
    Lib.HoverBridge {
        popup: pop
        widgetHovered: hov.hovered
    }
}
