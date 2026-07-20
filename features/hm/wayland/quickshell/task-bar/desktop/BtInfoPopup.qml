import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib

// Bar hover panel for the connected device, centered under the bar icon. Shows
// the same read-only info as the menu detail panel (battery / codec / profile /
// volume) and, for Pixel Buds, INTERACTIVE controls: ANC chips, volume-EQ / mono
// / speech-detection toggles, balance, and a collapsible 5-band EQ. Reads/writes
// go through the shared BluetoothService (single serial pbpctrl owner). Stays
// open while hovered (debounced) so the controls are usable; grabFocus:false so
// it never steals focus (pointer-only controls).
PopupWindow {
    id: tip

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var bt

    readonly property var dev: tip.bt.primaryAudio
    readonly property bool isBuds: tip.bt.audioIsBuds
    readonly property string sep: " " + String.fromCodePoint(0x00B7) + " "

    // Optimistic overrides applied immediately on a control change; cleared when
    // a fresh read confirms (bt.pbp changes). Codec lives in pw, so it has its
    // own optimistic cleared on pw refresh.
    property var opt: ({})
    property string optCodec: ""

    // Available codecs (card profiles) + the active one. Any audio device.
    readonly property var codecList: {
        var s = String(tip.bt.pw.codecs || "");
        if (s === "")
            return [];
        var out = [];
        var items = s.split(";");
        for (var i = 0; i < items.length; i++) {
            var kv = items[i].split("=");
            if (kv.length === 2)
                out.push({
                    "p": kv[0],
                    "l": kv[1]
                });
        }
        return out;
    }
    readonly property string codecActive: tip.optCodec !== "" ? tip.optCodec : String(tip.bt.pw.codecprofile || "")
    function eff(k) {
        if (tip.opt[k] !== undefined)
            return tip.opt[k];
        return tip.bt.pbp[k] !== undefined ? String(tip.bt.pbp[k]) : "";
    }
    function setOpt(k, v) {
        var o = {};
        for (var kk in tip.opt)
            o[kk] = tip.opt[kk];
        o[k] = v;
        tip.opt = o;
    }
    function num(k, d) {
        var v = tip.eff(k);
        return v === "" ? d : parseInt(v);
    }
    function eqArr() {
        var s = tip.eff("eq");
        var p = String(s).split(",");
        var r = [];
        for (var i = 0; i < 5; i++)
            r.push(p[i] !== undefined && p[i] !== "" ? parseInt(p[i]) : 0);
        return r;
    }
    function setEqBand(i, v) {
        var a = tip.eqArr();
        a[i] = Math.round(v);
        tip.setOpt("eq", a.join(","));
        tip.bt.pbpSet("eq", a.join(" "));
    }
    function setToggle(key, setting) {
        var nv = tip.eff(key) === "true" ? "false" : "true";
        tip.setOpt(key, nv);
        tip.bt.pbpSet(setting, nv);
    }

    property bool eqExpanded: false

    implicitWidth: 240
    implicitHeight: Math.max(card.implicitHeight, 1)
    color: "transparent"
    visible: false
    grabFocus: false

    anchor.window: tip.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    // Drive the service's audio polling only while we're open.
    Binding {
        target: tip.bt
        property: "hoverWants"
        value: tip.visible
    }

    // Persistent hover: stay open while the bar icon OR this panel is hovered;
    // close 250ms after both leave (bridges the gap between bar and popup).
    property bool iconHovered: false
    property bool panelHovered: false
    readonly property bool keepOpen: tip.iconHovered || tip.panelHovered
    onKeepOpenChanged: tip.keepOpen ? closeTimer.stop() : closeTimer.restart()
    property Timer closeTimer: Timer {
        interval: 250
        onTriggered: tip.hide()
    }

    function show() {
        var wc = tip.anchorItem.mapToItem(null, tip.anchorItem.width / 2, 0).x;
        tip.anchor.rect.x = Math.round(wc - tip.implicitWidth / 2);
        tip.anchor.rect.y = tip.barWindow.height + 4;
        tip.anchor.rect.width = 0;
        tip.anchor.rect.height = 0;
        tip.visible = true;
    }
    function hide() {
        tip.visible = false;
        tip.opt = {};
        tip.optCodec = "";
    }
    onVisibleChanged: if (!tip.visible)
        tip.eqExpanded = false
    // A fresh read confirms our optimistic state -> drop the overrides.
    Connections {
        target: tip.bt
        function onPbpChanged() {
            tip.opt = {};
        }
        function onPwChanged() {
            tip.optCodec = "";
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: body.implicitHeight + 20
        radius: 11
        color: tip.theme.bgCard
        border.width: 1
        border.color: tip.theme.border

        HoverHandler {
            onHoveredChanged: tip.panelHovered = hovered
        }

        ColumnLayout {
            id: body
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 6

            // --- No connected device --------------------------------------
            Text {
                Layout.fillWidth: true
                visible: !tip.dev
                text: !tip.bt.available ? "No Bluetooth adapter" : (!tip.bt.enabled ? "Bluetooth off" : "No device connected")
                color: tip.theme.textSecondary
                font.family: tip.theme.textFont
                font.pixelSize: 12
            }

            // --- Header ----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                visible: !!tip.dev
                spacing: 8
                Text {
                    text: tip.bt.typeGlyph(tip.dev ? tip.dev.icon : "")
                    color: tip.theme.accent
                    font.family: tip.theme.iconFont
                    font.pixelSize: 17
                }
                Text {
                    Layout.fillWidth: true
                    text: tip.dev ? (tip.dev.deviceName || tip.dev.name || tip.dev.address) : ""
                    color: tip.theme.textPrimary
                    font.family: tip.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            // Battery (per-bud for buds, else BlueZ aggregate).
            Text {
                Layout.fillWidth: true
                visible: !!tip.dev && (tip.batteryText !== "")
                text: tip.batteryText
                color: tip.theme.textSecondary
                font.family: tip.theme.textFont
                font.pixelSize: 11
            }
            // Codec chips (any connected audio device; PipeWire, fast).
            ColumnLayout {
                Layout.fillWidth: true
                visible: !!tip.dev && tip.codecList.length > 0
                spacing: 4
                Text {
                    text: "Codec"
                    color: tip.theme.textSecondary
                    font.family: tip.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: tip.codecList
                        Chip {
                            label: modelData.l
                            selected: tip.codecActive === modelData.p
                            onClicked: {
                                tip.optCodec = modelData.p;
                                tip.bt.codecSet(modelData.p);
                            }
                        }
                    }
                }
            }
            // Profile / volume (read-only).
            Text {
                Layout.fillWidth: true
                visible: !!tip.dev && tip.audioText !== ""
                text: tip.audioText
                color: tip.theme.textSecondary
                font.family: tip.theme.textFont
                font.pixelSize: 11
            }

            Rectangle {
                visible: tip.isBuds
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                height: 1
                color: tip.theme.border
            }

            // --- ANC chips -------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                visible: tip.isBuds && tip.eff("anc") !== ""
                spacing: 4
                Text {
                    text: "ANC"
                    color: tip.theme.textSecondary
                    font.family: tip.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Chip {
                        label: "Off"
                        selected: tip.eff("anc") === "off"
                        onClicked: {
                            tip.setOpt("anc", "off");
                            tip.bt.pbpSet("anc", "off");
                        }
                    }
                    Chip {
                        label: "Active"
                        selected: tip.eff("anc") === "active"
                        onClicked: {
                            tip.setOpt("anc", "active");
                            tip.bt.pbpSet("anc", "active");
                        }
                    }
                    Chip {
                        label: "Aware"
                        selected: tip.eff("anc") === "aware"
                        onClicked: {
                            tip.setOpt("anc", "aware");
                            tip.bt.pbpSet("anc", "aware");
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }

            // --- Toggles ---------------------------------------------------
            TogglePill {
                visible: tip.isBuds && tip.eff("volumeeq") !== ""
                label: "Volume EQ"
                on: tip.eff("volumeeq") === "true"
                onToggled: tip.setToggle("volumeeq", "volume-eq")
            }
            TogglePill {
                visible: tip.isBuds && tip.eff("mono") !== ""
                label: "Mono"
                on: tip.eff("mono") === "true"
                onToggled: tip.setToggle("mono", "mono")
            }
            TogglePill {
                visible: tip.isBuds && tip.eff("speech") !== ""
                label: "Speech detection"
                on: tip.eff("speech") === "true"
                onToggled: tip.setToggle("speech", "speech-detection")
            }

            // --- Balance ---------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                visible: tip.isBuds && tip.eff("balance") !== ""
                spacing: 2
                Text {
                    text: "Balance"
                    color: tip.theme.textSecondary
                    font.family: tip.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "L"
                        color: tip.theme.textSecondary
                        font.family: tip.theme.textFont
                        font.pixelSize: 10
                    }
                    Lib.MiniSlider {
                        id: balS
                        theme: tip.theme
                        Layout.fillWidth: true
                        from: -100
                        to: 100
                        onCommitted: tip.bt.pbpSet("balance", String(Math.round(v)))
                        Binding on value {
                            when: !balS.dragging
                            value: tip.num("balance", 0)
                        }
                    }
                    Text {
                        text: "R"
                        color: tip.theme.textSecondary
                        font.family: tip.theme.textFont
                        font.pixelSize: 10
                    }
                }
            }

            // --- Collapsible EQ -------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                visible: tip.isBuds && tip.eff("eq") !== ""
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "EQ"
                        color: tip.theme.textSecondary
                        font.family: tip.theme.textFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                    Text {
                        text: String.fromCodePoint(tip.eqExpanded ? 0xF0143 : 0xF0140) // chevron up/down
                        color: tip.theme.textSecondary
                        font.family: tip.theme.iconFont
                        font.pixelSize: 13
                    }
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: tip.eqExpanded = !tip.eqExpanded
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: tip.eqExpanded
                    spacing: 3
                    EqRow {
                        band: 0
                        label: "Low-bass"
                    }
                    EqRow {
                        band: 1
                        label: "Bass"
                    }
                    EqRow {
                        band: 2
                        label: "Mid"
                    }
                    EqRow {
                        band: 3
                        label: "Treble"
                    }
                    EqRow {
                        band: 4
                        label: "Up-treble"
                    }
                }
            }

            // --- Read-only footer -----------------------------------------
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: tip.isBuds && tip.footerText !== ""
                text: tip.footerText
                color: tip.theme.textSecondary
                font.family: tip.theme.textFont
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    // --- Derived display strings ---------------------------------------------
    readonly property string batteryText: {
        if (!tip.dev)
            return "";
        if (tip.isBuds && (String(tip.bt.pbp.left || "") !== "" || String(tip.bt.pbp.right || "") !== "")) {
            var s = "Battery   L " + (tip.bt.pbp.left || "?") + "%  R " + (tip.bt.pbp.right || "?") + "%";
            if (String(tip.bt.pbp["case"] || "") !== "")
                s += "  Case " + tip.bt.pbp["case"] + "%";
            return s;
        }
        return tip.dev.batteryAvailable ? ("Battery   " + Math.round(tip.dev.battery * 100) + "%") : "";
    }
    readonly property string audioText: {
        var parts = [];
        if (tip.bt.pw.profile)
            parts.push(tip.bt.pw.profile);
        if (tip.bt.pw.volume)
            parts.push("Vol " + tip.bt.pw.volume + "%");
        return parts.join(tip.sep);
    }
    readonly property string footerText: {
        var parts = [];
        if (tip.eff("multipoint") !== "")
            parts.push("Multipoint " + (tip.eff("multipoint") === "true" ? "on" : "off"));
        if (tip.eff("ohd") !== "")
            parts.push("On-head " + (tip.eff("ohd") === "true" ? "on" : "off"));
        if (tip.eff("firmware") !== "")
            parts.push("fw " + tip.eff("firmware"));
        return parts.join(tip.sep);
    }

    // --- Reusable controls ----------------------------------------------------
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal clicked
        implicitHeight: 22
        implicitWidth: chipText.implicitWidth + 18
        radius: 11
        color: chip.selected ? tip.theme.accent : (chipHover.hovered ? tip.theme.bgItemHover : tip.theme.bgItem)
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.selected ? tip.theme.textOnAccent : tip.theme.textPrimary
            font.family: tip.theme.textFont
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        HoverHandler {
            id: chipHover
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component TogglePill: RowLayout {
        id: tg
        property string label: ""
        property bool on: false
        signal toggled
        Layout.fillWidth: true
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: tg.label
            color: tip.theme.textSecondary
            font.family: tip.theme.textFont
            font.pixelSize: 11
        }
        Rectangle {
            implicitWidth: 32
            implicitHeight: 17
            radius: 8
            color: tg.on ? tip.theme.accent : tip.theme.bgItem
            Behavior on color {
                ColorAnimation {
                    duration: 130
                }
            }
            Rectangle {
                width: 13
                height: 13
                radius: 6.5
                y: 2
                x: tg.on ? parent.width - width - 2 : 2
                color: tip.theme.textOnAccent
                Behavior on x {
                    NumberAnimation {
                        duration: 130
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tg.toggled()
            }
        }
    }

    component EqRow: RowLayout {
        id: er
        property int band: 0
        property string label: ""
        Layout.fillWidth: true
        spacing: 6
        Text {
            Layout.preferredWidth: 60
            text: er.label
            color: tip.theme.textSecondary
            font.family: tip.theme.textFont
            font.pixelSize: 10
        }
        Lib.MiniSlider {
            id: eqSlider
            theme: tip.theme
            Layout.fillWidth: true
            from: -6
            to: 6
            onCommitted: tip.setEqBand(er.band, v)
            Binding on value {
                when: !eqSlider.dragging
                value: tip.eqArr()[er.band]
            }
        }
        Text {
            Layout.preferredWidth: 16
            horizontalAlignment: Text.AlignRight
            text: tip.eqArr()[er.band]
            color: tip.theme.textPrimary
            font.family: tip.theme.textFont
            font.pixelSize: 10
        }
    }
}
