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

    // An absent reading arrives from JSON as null, and `null` is neither
    // undefined nor NaN -- string-concatenating it yields "null%". Every
    // numeric field below is optional, so they all route through this.
    function hasVal(v) {
        return v !== null && v !== undefined && !isNaN(v);
    }

    // A neighbour stronger than the serving cell means the modem is camped on
    // a worse cell than one it can see. Compared against the LTE anchor's RSRP
    // from QENG rather than cellular.rsrp, which reports the NR leg -- an NR
    // RSRP against an LTE neighbour's is not a comparison.
    readonly property bool betterNeighbour: {
        var n = pop.svc.cellular.neighbours;
        var s = pop.svc.cellular.serving;
        if (!n || !s || !pop.hasVal(n.best_rsrp))
            return false;
        var lte = (s.cells || []).filter(function (c) { return c.rat === "LTE"; });
        if (lte.length === 0 || !pop.hasVal(s.rsrp))
            return false;
        return n.best_rsrp > s.rsrp;
    }

    readonly property bool lowBattery: pop.hasVal(pop.svc.battery.percent)
        && pop.hasVal(pop.svc.battery.warn_capacity)
        && pop.svc.battery.percent <= pop.svc.battery.warn_capacity

    // Tint from the MCU's own high-temperature threshold, IGNORING its enable
    // flag. Both warnings ship disabled on this router, so inheriting `enable`
    // would leave the popup green at 51C -- the router declining to alert is
    // not a reason for the popup to stay quiet. Yellow enters 10C below the
    // threshold so the number is actionable before it is a warning.
    function tempColor(t, warn) {
        if (!pop.hasVal(t) || !pop.hasVal(warn))
            return pop.theme.textSecondary;
        if (t >= warn)
            return pop.theme.accentRed;
        return t >= warn - 10 ? pop.theme.accentYellow : pop.theme.textSecondary;
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
                // `!== undefined` alone was not enough: an absent reading
                // arrives from JSON as null, not undefined, and rendered
                // literally as "null%".
                Text {
                    text: pop.hasVal(pop.svc.battery.percent)
                        ? (pop.svc.battery.percent + "%") : "--"
                    font.family: pop.theme.iconFont; font.pixelSize: 12
                    color: pop.svc.battery.charging ? pop.theme.accentGreen
                         : pop.lowBattery ? pop.theme.accentRed
                         : pop.theme.textPrimary
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
                    // operator_label carries the SIM's own brand beside the
                    // network it rides ("Mint (T-Mobile)"), marked "R:" while
                    // roaming. Falls back to device.carrier, which is now
                    // derived from the same values rather than hardcoded.
                    Text {
                        text: (pop.svc.cellular.gen || "?") + "   "
                            + (pop.svc.cellular.operator_label || pop.svc.device.carrier || "")
                        font.family: pop.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: pop.theme.textPrimary
                    }
                    // Roaming is worth its own mark, not just a prefix buried
                    // in the name: it is the state that costs money.
                    Text {
                        visible: pop.svc.cellular.roaming === true
                        text: "ROAMING"
                        font.family: pop.theme.iconFont; font.pixelSize: 9; font.weight: Font.DemiBold
                        color: pop.theme.accentYellow
                    }
                }
                // Registration + PLMN: the facts behind the name above. Shown
                // only once known, so nothing renders "undefined" before the
                // first AT read lands.
                RowLayout {
                    spacing: 12
                    visible: !!pop.svc.cellular.plmn || !!pop.svc.cellular.registration
                    Text {
                        visible: !!pop.svc.cellular.plmn
                        text: "PLMN " + (pop.svc.cellular.plmn || "")
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                    Text {
                        visible: !!pop.svc.cellular.registration
                        text: pop.svc.cellular.registration || ""
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.svc.cellular.roaming === true
                            ? pop.theme.accentYellow : pop.theme.textSecondary
                    }
                    Text {
                        visible: !!pop.svc.cellular.sim_operator
                        text: "SIM " + (pop.svc.cellular.sim_operator || "")
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
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
                // Serving cell (from AT+QENG="servingcell"), plus its identity.
                // Cell id and TAC are here because a CHANGE in either is a
                // handover -- the value itself is only a landmark.
                RowLayout {
                    id: servingRow
                    property var serving: pop.svc.cellular.serving
                    property var nbr: pop.svc.cellular.neighbours
                    visible: !!servingRow.serving
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: servingRow.serving
                            ? ("Serving  " + (servingRow.serving.bands || []).join(" + ")) : ""
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                    Text {
                        visible: !!(servingRow.serving && servingRow.serving.cellid)
                        text: servingRow.serving
                            ? ("cell " + servingRow.serving.cellid
                               + (servingRow.serving.tac ? ("  TAC " + servingRow.serving.tac) : ""))
                            : ""
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                    // Neighbours, with the serving cell already filtered out.
                    // Yellow when one is stronger than the cell we are camped
                    // on, which is the only actionable reading here -- a list
                    // of weaker cells is just noise.
                    Text {
                        visible: !!servingRow.nbr
                        text: servingRow.nbr
                            ? (servingRow.nbr.count + " nbr"
                               + (pop.hasVal(servingRow.nbr.best_rsrp)
                                  ? ("  best " + servingRow.nbr.best_rsrp) : ""))
                            : ""
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.betterNeighbour ? pop.theme.accentYellow
                                                   : pop.theme.textSecondary
                    }
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

            // --- Connection facts ---
            // What the uplink actually got: the bearer it dialled and the lease
            // behind it. All of this comes from calls already being made -- the
            // APN rides along in cellular.sim status, the rest in the
            // network.interface.modem_cpu status read that carries the uptime.
            ColumnLayout {
                visible: pop.svc.reachable && (!!pop.svc.cellular.apn
                         || !!pop.svc.uplink.ip)
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        visible: !!pop.svc.cellular.apn
                        text: "APN  " + (pop.svc.cellular.apn || "")
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: !!pop.svc.uplink.device
                        text: pop.svc.uplink.device || ""
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: !!pop.svc.uplink.ip
                    Text {
                        text: "IP  " + (pop.svc.uplink.ip || "")
                            + (pop.hasVal(pop.svc.uplink.mask)
                               ? ("/" + pop.svc.uplink.mask) : "")
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: !!pop.svc.uplink.gateway
                        text: "gw " + (pop.svc.uplink.gateway || "")
                        font.family: pop.theme.iconFont; font.pixelSize: 10
                        color: pop.theme.textSecondary
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: (pop.svc.uplink.dns || []).length > 0
                    text: "DNS  " + (pop.svc.uplink.dns || []).join("  ")
                    elide: Text.ElideRight
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
            }

            // --- Battery ---
            // This is a battery-powered router and the popup showed nothing
            // but a bare percentage in the header. Temperature, wear and the
            // abnormal flag all come from `mcu status`.
            RowLayout {
                visible: pop.svc.reachable && (pop.hasVal(pop.svc.battery.temp)
                         || pop.hasVal(pop.svc.battery.cycles))
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: String.fromCharCode(pop.svc.battery.charging ? 0xF0E7 // bolt
                                                                       : 0xF241) // battery-half
                    font.family: pop.theme.faFont; font.pixelSize: 10
                    color: pop.svc.battery.charging ? pop.theme.accentGreen
                                                    : pop.theme.textSecondary
                }
                Text {
                    text: pop.svc.battery.charging
                        ? (pop.svc.battery.fastcharge ? "fast charging" : "charging")
                        : (pop.svc.battery.plugged ? "plugged" : "on battery")
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                Text {
                    visible: pop.hasVal(pop.svc.battery.temp)
                    text: pop.svc.battery.temp + "C"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.tempColor(pop.svc.battery.temp,
                                         pop.svc.battery.warn_temp)
                }
                Item { Layout.fillWidth: true }
                // Charge cycles: wear, not state. Worth knowing on a device
                // that lives on its battery.
                Text {
                    visible: pop.hasVal(pop.svc.battery.cycles)
                    text: pop.svc.battery.cycles + " cycles"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                // The MCU's own fault flag. Rare enough that it earns red.
                Text {
                    visible: pop.svc.battery.abnormal === true
                    text: "ABNORMAL"
                    font.family: pop.theme.iconFont; font.pixelSize: 9
                    font.weight: Font.DemiBold
                    color: pop.theme.accentRed
                }
            }

            // --- Health ---
            // Two uptimes, deliberately. `system` is how long the router has
            // been powered; `modem` is how long since the uplink last dialled.
            // The GAP between them is the signal -- a link that keeps
            // redialling sits far below the system uptime while a stable one
            // tracks it, and neither number alone carries that.
            RowLayout {
                visible: pop.svc.reachable
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "CPU " + (pop.svc.system.cpu_temp || "--") + "C   load "
                        + ((pop.svc.system.load || [])[0] || "--")
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                // Free memory, not used: the number that answers "is the web
                // UI about to crawl". buff/cache is reclaimable so it counts
                // as free, matching what the router itself reports.
                Text {
                    visible: pop.hasVal(pop.svc.system.mem_total)
                        && pop.hasVal(pop.svc.system.mem_free)
                    text: "mem " + RouterFmt.fmtBytes((pop.svc.system.mem_free || 0)
                                                      + (pop.svc.system.mem_buff || 0))
                        + " free"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "sys " + RouterFmt.fmtDuration(pop.svc.system.uptime)
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
                Text {
                    text: "modem " + RouterFmt.fmtDuration(pop.svc.uplink.uptime)
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.theme.textSecondary
                }
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
                        { label: "Reboot router", action: "reboot" }
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
