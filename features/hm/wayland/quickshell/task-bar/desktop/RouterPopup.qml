import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib/routerfmt.js" as RouterFmt

PopupWindow {
    id: pop
    required property QtObject theme
    required property var svc
    required property var barWindow
    required property var anchorItem
    property bool contentHovered: cardHover.hovered

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    onImplicitWidthChanged: if (pop.visible) Qt.callLater(pop.reclamp)
    color: "transparent"
    visible: false
    grabFocus: false
    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function reclamp() {
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
    }
    function show() { if (!pop.visible) { pop.reclamp(); pop.visible = true; } }
    function hide() { pop.visible = false; }

    function qColor(q) {
        return q === "excellent" ? pop.theme.accentGreen
             : q === "good" ? pop.theme.accentBlue
             : q === "fair" ? pop.theme.accentYellow : pop.theme.accentRed;
    }

    Rectangle {
        id: card
        implicitWidth: 380
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        HoverHandler { id: cardHover }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            // --- Not-connected card ---
            Text {
                visible: !pop.svc.reachable
                text: "Not connected to GL-E5800"
                font.family: pop.theme.iconFont
                font.pixelSize: 12
                color: pop.theme.textSecondary
            }

            // --- Header ---
            RowLayout {
                visible: pop.svc.reachable
                Layout.fillWidth: true
                Text {
                    text: pop.svc.device.model || "GL-E5800"
                    font.family: pop.theme.iconFont; font.pixelSize: 13; font.weight: Font.Bold
                    color: pop.theme.textPrimary
                }
                Item { Layout.fillWidth: true }
                RowLayout {
                    spacing: 4
                    Text {
                        text: String.fromCharCode(0xF111) // fa circle
                        font.family: pop.theme.faFont; font.pixelSize: 9
                        color: pop.svc.uplink.online ? pop.theme.accentGreen : pop.theme.accentRed
                    }
                    Text {
                        text: pop.svc.uplink.online ? "online" : "offline"
                        font.family: pop.theme.iconFont; font.pixelSize: 11
                        color: pop.svc.uplink.online ? pop.theme.accentGreen : pop.theme.accentRed
                    }
                }
                Text {
                    text: (pop.svc.battery.percent !== undefined ? pop.svc.battery.percent + "%" : "--")
                    font.family: pop.theme.iconFont; font.pixelSize: 12
                    color: pop.svc.battery.charging ? pop.theme.accentGreen : pop.theme.textPrimary
                }
            }

            // --- Re-auth banner: reachable but SSH key rejected (factory reset) ---
            Rectangle {
                visible: pop.svc.reachable && pop.svc.authError
                Layout.fillWidth: true
                implicitHeight: authCol.implicitHeight + 12
                radius: 4
                color: Qt.rgba(pop.theme.accentRed.r, pop.theme.accentRed.g, pop.theme.accentRed.b, 0.15)
                border.width: 1
                border.color: pop.theme.accentRed
                ColumnLayout {
                    id: authCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                    spacing: 2
                    RowLayout {
                        spacing: 6
                        Text {
                            text: String.fromCharCode(0xF071) // fa exclamation-triangle
                            font.family: pop.theme.faFont; font.pixelSize: 11
                            color: pop.theme.accentRed
                        }
                        Text {
                            text: "SSH key rejected"
                            font.family: pop.theme.iconFont; font.pixelSize: 11; font.weight: Font.Bold
                            color: pop.theme.accentRed
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "The router rejected the key (likely factory-reset). Re-run the "
                            + "E5800 key setup: re-add the e5800poll public key and clear the pinned "
                            + "host key, then it reconnects."
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                }
            }

            // --- Cellular hero ---
            ColumnLayout {
                visible: pop.svc.reachable && !pop.svc.authError && (pop.svc.cellular.supported !== false)
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    spacing: 8
                    Text {
                        text: (pop.svc.cellular.gen || "?") + "   " + (pop.svc.device.carrier || "")
                        font.family: pop.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: pop.theme.textPrimary
                    }
                }
                RowLayout {
                    spacing: 12
                    Text {
                        text: "RSRP " + (pop.svc.cellular.rsrp !== undefined ? pop.svc.cellular.rsrp : "--")
                        font.family: pop.theme.iconFont; font.pixelSize: 11
                        color: pop.qColor(RouterFmt.quality("rsrp", pop.svc.cellular.rsrp))
                    }
                    Text {
                        text: "RSRQ " + (pop.svc.cellular.rsrq !== undefined ? pop.svc.cellular.rsrq : "--")
                        font.family: pop.theme.iconFont; font.pixelSize: 11
                        color: pop.qColor(RouterFmt.quality("rsrq", pop.svc.cellular.rsrq))
                    }
                    Text {
                        text: "SINR " + (pop.svc.cellular.sinr !== undefined ? pop.svc.cellular.sinr : "--")
                        font.family: pop.theme.iconFont; font.pixelSize: 11
                        color: pop.qColor(RouterFmt.quality("sinr", pop.svc.cellular.sinr))
                    }
                    Text {
                        text: pop.svc.cellular.network_type || ""
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                }
                // Aggregation: component carriers from AT+QCAINFO, each colored by
                // activation state -- green = moving data (state 2 / PCC / NR
                // PSCell), default = configured-idle (state 1), dim = deconfigured
                // (state 0). Mirrors the Wi-Fi chip row pattern below.
                RowLayout {
                    id: aggRow
                    property var ca: pop.svc.cellular.ca
                    visible: !!ca && (ca.carriers || []).length > 0
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "Aggregation"
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                    Repeater {
                        model: aggRow.ca ? aggRow.ca.carriers : []
                        delegate: Text {
                            required property var modelData
                            required property int index
                            text: (index === 0 ? "" : "+ ") + modelData.label
                            font.family: pop.theme.iconFont; font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: modelData.active ? pop.theme.accentGreen
                                 : (modelData.state === 0 ? pop.theme.textSecondary
                                    : pop.theme.textPrimary)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                // Serving cell (from AT+QENG="servingcell").
                Text {
                    property var serving: pop.svc.cellular.serving
                    visible: !!serving
                    text: serving ? ("Serving  " + (serving.bands || []).join(" + ")) : ""
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
            }

            // --- Throughput + data used ---
            RowLayout {
                visible: pop.svc.reachable
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "dn " + RouterFmt.fmtRate(pop.svc.throughput.rx)
                        + "   up " + RouterFmt.fmtRate(pop.svc.throughput.tx)
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textPrimary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "used " + RouterFmt.fmtBytes((pop.svc.dataUsage.cycle_rx || 0)
                                                       + (pop.svc.dataUsage.cycle_tx || 0))
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textSecondary
                }
            }

            // --- Health ---
            Text {
                visible: pop.svc.reachable
                text: "CPU " + (pop.svc.system.cpu_temp || "--") + "C   load "
                    + ((pop.svc.system.load || [])[0] || "--") + "   up "
                    + Math.floor((pop.svc.system.uptime || 0) / 3600) + "h"
                font.family: pop.theme.iconFont; font.pixelSize: 10
                color: pop.theme.textSecondary
            }

            // --- WiFi (one token per radio, green when active; guest shown as "g") + VPN ---
            RowLayout {
                visible: pop.svc.reachable
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "Wi-Fi"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                Repeater {
                    model: pop.svc.wifi || []
                    delegate: Text {
                        required property var modelData
                        text: modelData.guest ? "g" : (modelData.band || "?")
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: modelData.up ? pop.theme.accentGreen : pop.theme.textSecondary
                        opacity: modelData.up ? 1.0 : 0.45
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "VPN  " + (pop.svc.vpn.active ? pop.svc.vpn.name : "(none)")
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.svc.vpn.active ? pop.theme.accentGreen : pop.theme.textSecondary
                }
            }

            // --- Clients ---
            // Only build the client ListView while the popup is open: svc.clients
            // is refreshed every 2s by the bar poll, so an always-live ListView
            // here would rebuild all its delegates every tick even while the popup
            // is hidden. The Loader collapses to zero height when inactive.
            Loader {
                Layout.fillWidth: true
                active: pop.visible && pop.svc.reachable
                sourceComponent: RouterClients {
                    theme: pop.theme
                    clients: pop.svc.clients.list || []
                }
            }

            // --- Recovery buttons ---
            RowLayout {
                visible: pop.svc.reachable
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: pop.svc.recovering ? ("Recovering: " + (pop.svc.data.recovery
                          ? pop.svc.data.recovery.action : "") + "...") : "Recover:"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                Repeater {
                    model: [
                        { label: "Redial", action: "redial" },
                        { label: "Airplane", action: "airplane" },
                        { label: "Reboot", action: "reboot" }
                    ]
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        property bool armed: false
                        width: txt.implicitWidth + 16
                        height: 20
                        radius: 4
                        opacity: pop.svc.recovering ? 0.4 : 1.0
                        color: btn.armed ? pop.theme.accentRed : pop.theme.bgItem
                        Text {
                            id: txt
                            anchors.centerIn: parent
                            text: btn.armed ? "confirm?" : btn.modelData.label
                            font.family: pop.theme.iconFont; font.pixelSize: 10
                            color: btn.armed ? pop.theme.textOnAccent : pop.theme.textSecondary
                        }
                        Timer { id: disarm; interval: 4000; onTriggered: btn.armed = false }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !pop.svc.recovering
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!btn.armed) { btn.armed = true; disarm.restart(); }
                                else { btn.armed = false; pop.svc.reconnect(btn.modelData.action); }
                            }
                        }
                    }
                }
            }
        }
    }
}
