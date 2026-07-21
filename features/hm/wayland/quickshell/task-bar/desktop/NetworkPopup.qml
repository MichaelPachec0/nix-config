import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../lib" as Lib

// WiFi click menu: header (Wi-Fi on/off + rescan) over two deduped,
// signal-sorted lists -- Saved on top, Available below (scrollable). Clicking
// connects to open/saved networks, prompts for a password on new secured ones,
// or disconnects the active one. Hovering a row reveals a per-AP detail panel to
// the right (ApInfoPopup); saved networks get a Forget button there. The panel
// lives inside this window so it shares the focus grab (a separate popup window
// never receives hover/clicks while this menu holds the grab).
PopupWindow {
    id: pop

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var net // Lib.NetworkService
    property var networks: []

    readonly property int listW: 280
    readonly property int infoW: 250
    // The hovered AP (and whether it's saved) -> drives the detail panel. The
    // panel lives INSIDE this window (the menu's focus grab steals pointer events
    // from a separate popup window), and the window widens to fit it on hover.
    property var hoverAp: null
    property bool hoverSaved: false
    // Keep the panel alive while the cursor is over the list OR the detail panel.
    // These track hover on the CONTENT items directly (the list card is the rows'
    // ancestor; hover propagates child->ancestor reliably). A sibling layer behind
    // the list does NOT receive hover dependably -- it dropped while a row was
    // still hovered, which collapsed the panel. A short debounce bridges the small
    // gap between the list and the panel.
    property bool listHover: false
    property bool panelHover: false
    readonly property bool overMenu: pop.listHover || pop.panelHover
    onOverMenuChanged: pop.overMenu ? collapseTimer.stop() : collapseTimer.restart()
    // Show the detail panel only while hovering an AP and not entering a password.
    readonly property bool showInfo: pop.hoverAp !== null && pop.pwSsid === ""

    // Fixed size -- the panel's space is always reserved (transparent when empty)
    // so the window NEVER resizes on hover. Resizing the surface under the pointer
    // makes the cursor and the moving edge race, which the compositor reports as a
    // spurious leave and collapses the panel mid-hover. A constant size avoids it
    // entirely; the height bound (260) always fits the detail panel.
    implicitWidth: pop.listW + 4 + pop.infoW
    implicitHeight: Math.max(card.implicitHeight, 260)
    color: "transparent"
    visible: false
    grabFocus: true
    onVisibleChanged: if (!pop.visible) {
        pop.hoverAp = null;
        pop.pwSsid = "";
    }

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    // Pin the left edge and grow rightward when the detail panel appears, so the
    // list never re-centers / shifts once rendered (gravity without a horizontal
    // component centers the popup, moving the list when the window widens).
    anchor.gravity: Edges.Bottom | Edges.Right

    function toggle() {
        if (pop.visible) {
            pop.visible = false;
            return;
        }
        // Center the list under the widget (as before), but pin that left edge
        // so the window only grows rightward for the panel -- the list never
        // moves once shown. (Left edge = list center - listW/2.)
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = x - pop.listW / 2;
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.selectedTab = pop.net.defaultTab();
        pop.visible = true;
    }

    function netGlyph(signal) {
        if (signal <= 25)
            return String.fromCodePoint(0xF091F);
        if (signal <= 50)
            return String.fromCodePoint(0xF0922);
        if (signal <= 75)
            return String.fromCodePoint(0xF0925);
        return String.fromCodePoint(0xF0928);
    }

    // Active tab: "wifi" | "ethernet" | "vpn".
    property string selectedTab: "wifi"
    // Tab visibility helpers.
    readonly property bool showEthTab: pop.net.ethernetConns.length > 0
    readonly property bool showVpnTab: pop.net.vpns.length > 0

    // Saved wifi connection names (~= SSIDs) so secured-but-saved networks
    // connect directly instead of prompting for a password.
    property var savedSet: ({})
    // Non-empty while prompting for a new secured network's password.
    property string pwSsid: ""

    function onNetClicked(net) {
        if (net.inuse) {
            Quickshell.execDetached(["nmcli", "-w", "10", "connection", "down", "id", net.ssid]);
            pop.visible = false;
        } else if (!net.secured) {
            Quickshell.execDetached(["nmcli", "-w", "10", "dev", "wifi", "connect", net.ssid]);
            pop.visible = false;
        } else if (pop.savedSet[net.ssid]) {
            Quickshell.execDetached(["nmcli", "-w", "15", "dev", "wifi", "connect", net.ssid]);
            pop.visible = false;
        } else {
            pop.pwSsid = net.ssid; // -> password view
        }
    }
    function connectWithPassword(pw) {
        if (!pw || pw.length === 0)
            return;
        Quickshell.execDetached(["nmcli", "-w", "20", "dev", "wifi", "connect", pop.pwSsid, "password", pw]);
        pop.pwSsid = "";
        pop.visible = false;
    }

    // Saved networks on top, the rest below.
    readonly property var savedNets: pop.networks.filter(function (n) {
        return pop.savedSet[n.ssid] === true;
    })
    readonly property var otherNets: pop.networks.filter(function (n) {
        return pop.savedSet[n.ssid] !== true;
    })

    // Shared delegate for both lists.
    Component {
        id: netRowDelegate
        Rectangle {
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            height: 30
            radius: 6
            color: rowHover.hovered ? pop.theme.bgItemHover : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 10
                spacing: 8
                Text {
                    text: pop.netGlyph(modelData.signal)
                    color: modelData.inuse ? pop.theme.accent : pop.theme.textSecondary
                    font.family: pop.theme.iconFont
                    font.pixelSize: 16
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.ssid
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    visible: modelData.secured
                    text: String.fromCodePoint(0xF033E) // lock
                    color: pop.theme.textSecondary
                    font.family: pop.theme.iconFont
                    font.pixelSize: 12
                }
                Text {
                    visible: modelData.inuse
                    text: String.fromCodePoint(0xF012C) // check
                    color: pop.theme.accent
                    font.family: pop.theme.iconFont
                    font.pixelSize: 14
                }
            }
            HoverHandler {
                id: rowHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered) {
                    pop.hoverAp = modelData;
                    pop.hoverSaved = pop.savedSet[modelData.ssid] === true;
                }
            }
            TapHandler {
                onTapped: pop.onNetClicked(modelData)
            }
        }
    }

    Lib.CommandPoll {
        id: scan
        interval: 6000
        running: pop.visible && pop.net.wifiRadio && pop.selectedTab === "wifi"
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/net-scan.sh"]
        parse: function (o) {
            var seen = {};
            var nets = [];
            var wbss = {}; // BSSID -> {dbm, age} from wpa_supplicant
            String(o).split(/\r?\n/).forEach(function (line) {
                if (!line)
                    return;
                if (line.indexOf("WBSS:") === 0) {
                    var w = line.split(":"); // WBSS:46:A5:..:18:-40:12
                    if (w.length >= 9)
                        wbss[w.slice(1, 7).join(":").toUpperCase()] = {
                            dbm: parseInt(w[7], 10),
                            age: parseInt(w[8], 10)
                        };
                    return;
                }
                // nmcli -t escapes ':' in values as '\:' -> sentinel-swap, split,
                // restore. Fields: IN-USE,SIGNAL,SECURITY,CHAN,FREQ,RATE,
                // BANDWIDTH,MODE,RSN-FLAGS,BSSID,SSID.
                var parts = line.replace(/\\:/g, "@@C@@").split(":");
                if (parts.length < 11)
                    return;
                for (var j = 0; j < parts.length; j++)
                    parts[j] = parts[j].replace(/@@C@@/g, ":");
                var ssid = parts.slice(10).join(":");
                if (!ssid)
                    return; // hidden network
                var inuse = parts[0].trim() === "*";
                var signal = parseInt(parts[1], 10) || 0;
                var rsn = parts[8];
                var secured = (rsn !== "" && rsn !== "(none)") || (parts[2] !== "" && parts[2] !== "--");
                var n = {
                    ssid: ssid,
                    signal: signal,
                    secured: secured,
                    inuse: inuse,
                    chan: parts[3],
                    freq: parseInt(parts[4], 10) || 0,
                    rate: parts[5],
                    bandwidth: parts[6],
                    mode: parts[7],
                    rsn: rsn,
                    bssid: parts[9]
                };
                if (seen[ssid] !== undefined) {
                    var e = nets[seen[ssid]];
                    if (signal > e.signal) {
                        n.inuse = e.inuse || inuse;
                        nets[seen[ssid]] = n;
                    } else if (inuse) {
                        e.inuse = true;
                    }
                    return;
                }
                seen[ssid] = nets.length;
                nets.push(n);
            });
            nets.forEach(function (n) {
                var w = wbss[String(n.bssid).toUpperCase()];
                if (w) {
                    n.dbm = w.dbm;
                    n.age = w.age;
                }
            });
            nets.sort(function (a, b) {
                if (a.inuse !== b.inuse)
                    return a.inuse ? -1 : 1;
                return b.signal - a.signal;
            });
            return nets;
        }
        onUpdated: pop.networks = value
    }

    // Saved wifi connection names (~= SSID) -> savedSet.
    Lib.CommandPoll {
        interval: 10000
        running: pop.visible && pop.net.wifiRadio && pop.selectedTab === "wifi"
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/net-saved-wifi.sh"]
        parse: function (o) {
            var set = {};
            String(o).split(/\r?\n/).forEach(function (l) {
                if (l)
                    set[l] = true;
            });
            return set;
        }
        onUpdated: pop.savedSet = value
    }

    // Debounce so a brief excursion off the content (the small list<->panel gap)
    // doesn't collapse the panel; a real leave has no return and fires after the
    // interval. Driven by overMenu (listHover || panelHover) above.
    Timer {
        id: collapseTimer
        interval: 180
        onTriggered: pop.hoverAp = null
    }

    Rectangle {
        id: card
        width: pop.listW
        implicitHeight: col.implicitHeight + 16
        radius: 11
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        // Hover detector for the whole list. card is the rows' ancestor, so this
        // is true whenever any row is hovered -- hover propagates child->ancestor.
        HoverHandler {
            id: listHoverHandler
            onHoveredChanged: pop.listHover = hovered
        }

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 8

            // Tab bar: one header per category that has profiles. Left-click selects;
            // the active-category header carries a dot. Wi-Fi is always present when a
            // Wi-Fi device exists.
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [
                        {key: "wifi", label: "Wi-Fi", show: pop.net.hasWifi, active: pop.net.primaryType === "wifi" && pop.net.connState === "activated"},
                        {key: "ethernet", label: "Ethernet", show: pop.showEthTab, active: pop.net.primaryType === "ethernet" && pop.net.connState === "activated"},
                        {key: "vpn", label: "VPN", show: pop.showVpnTab, active: pop.net.vpnActive}
                    ]
                    RowLayout {
                        required property var modelData
                        visible: modelData.show
                        spacing: 4
                        Text {
                            text: modelData.label
                            color: pop.selectedTab === modelData.key ? pop.theme.accent : pop.theme.textSecondary
                            font.family: pop.theme.textFont
                            font.pixelSize: 12
                            font.weight: pop.selectedTab === modelData.key ? Font.Bold : Font.Normal
                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                onTapped: pop.selectedTab = modelData.key
                            }
                        }
                        Rectangle {
                            visible: modelData.active
                            implicitWidth: 5
                            implicitHeight: 5
                            radius: 999
                            color: pop.theme.accentGreen
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            // Header: title + rescan + on/off toggle
            RowLayout {
                Layout.fillWidth: true
                visible: pop.selectedTab === "wifi"
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi"
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
                // Rescan
                Text {
                    visible: pop.net.wifiRadio
                    text: String.fromCodePoint(0xF0450)
                    color: rescanHover.hovered ? pop.theme.accent : pop.theme.textSecondary
                    font.family: pop.theme.iconFont
                    font.pixelSize: 15
                    HoverHandler {
                        id: rescanHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"])
                    }
                }
                // On/off toggle pill
                Rectangle {
                    width: 34
                    height: 18
                    radius: 9
                    color: pop.net.wifiRadio ? pop.theme.accent : pop.theme.bgItem
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                    Rectangle {
                        width: 14
                        height: 14
                        radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: pop.net.wifiRadio ? parent.width - width - 2 : 2
                        color: "white"
                        Behavior on x {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["nmcli", "radio", "wifi", pop.net.wifiRadio ? "off" : "on"])
                    }
                }
            }

            // Disconnect button: visible only when a Wi-Fi connection is active.
            Rectangle {
                Layout.fillWidth: true
                visible: pop.selectedTab === "wifi" && pop.net.wifiUuid !== ""
                implicitHeight: 30
                radius: 8
                color: dcHover.hovered ? Qt.rgba(pop.theme.accentRed.r, pop.theme.accentRed.g, pop.theme.accentRed.b, 0.18) : Qt.rgba(pop.theme.accentRed.r, pop.theme.accentRed.g, pop.theme.accentRed.b, 0.10)
                Text {
                    anchors.centerIn: parent
                    text: "Disconnect"
                    color: pop.theme.accentRed
                    font.family: pop.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: dcHover
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pop.net.disconnect()
                }
            }

            // Off message
            Text {
                visible: pop.selectedTab === "wifi" && !pop.net.wifiRadio
                Layout.fillWidth: true
                text: "Wi-Fi is off"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 12
            }

            // Saved networks -- all in view (no scroll).
            Text {
                visible: pop.selectedTab === "wifi" && pop.net.wifiRadio && pop.pwSsid === "" && pop.savedNets.length > 0
                Layout.fillWidth: true
                text: "Saved"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 10
                font.weight: Font.Bold
            }
            ListView {
                visible: pop.selectedTab === "wifi" && pop.net.wifiRadio && pop.pwSsid === "" && pop.savedNets.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                interactive: false
                spacing: 1
                model: pop.savedNets
                delegate: netRowDelegate
            }

            // Available (unsaved) networks -- scrollable.
            Text {
                visible: pop.selectedTab === "wifi" && pop.net.wifiRadio && pop.pwSsid === "" && pop.otherNets.length > 0
                Layout.fillWidth: true
                text: "Available"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 10
                font.weight: Font.Bold
            }
            ListView {
                id: otherList
                visible: pop.selectedTab === "wifi" && pop.net.wifiRadio && pop.pwSsid === "" && pop.otherNets.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 240)
                clip: true
                spacing: 1
                boundsBehavior: Flickable.StopAtBounds
                model: pop.otherNets
                delegate: netRowDelegate

                readonly property bool overflowing: contentHeight > height
                ScrollBar.vertical: ScrollBar {
                    id: vbar
                    policy: otherList.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    width: 6
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: vbar.pressed ? pop.theme.accent : pop.theme.bgItemHover
                        opacity: vbar.active ? 1.0 : 0.85
                    }
                    background: Rectangle {
                        color: "transparent"
                    }
                }
            }

            // Password prompt for a new secured network.
            ColumnLayout {
                visible: pop.selectedTab === "wifi" && pop.pwSsid !== ""
                Layout.fillWidth: true
                spacing: 8
                onVisibleChanged: if (visible) {
                    pwField.text = "";
                    pwField.forceActiveFocus();
                }

                Text {
                    Layout.fillWidth: true
                    text: "Password for " + pop.pwSsid
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                TextField {
                    id: pwField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    color: pop.theme.textPrimary
                    placeholderTextColor: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 12
                    selectByMouse: true
                    background: Rectangle {
                        radius: 6
                        color: pop.theme.bgItem
                        border.width: 1
                        border.color: pwField.activeFocus ? pop.theme.accent : pop.theme.border
                    }
                    onAccepted: pop.connectWithPassword(text)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 6
                        color: cancelHover.hovered ? pop.theme.bgItemHover : pop.theme.bgItem
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: pop.theme.textPrimary
                            font.family: pop.theme.textFont
                            font.pixelSize: 12
                        }
                        HoverHandler {
                            id: cancelHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: pop.pwSsid = ""
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 6
                        color: connectHover.hovered ? Qt.darker(pop.theme.accent, 1.1) : pop.theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "Connect"
                            color: pop.theme.textOnAccent
                            font.family: pop.theme.textFont
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                        HoverHandler {
                            id: connectHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: pop.connectWithPassword(pwField.text)
                        }
                    }
                }
            }

            // Ethernet tab body.
            NetworkProfileList {
                Layout.fillWidth: true
                visible: pop.selectedTab === "ethernet"
                theme: pop.theme
                net: pop.net
                conns: pop.net.ethernetConns
                emptyText: "No wired connections"
            }

            // VPN tab body.
            NetworkProfileList {
                Layout.fillWidth: true
                visible: pop.selectedTab === "vpn"
                theme: pop.theme
                net: pop.net
                conns: pop.net.vpns
                emptyText: "No VPN connections"
            }
        }
    }

    // Per-AP detail panel, to the right of the list (4px gap), inside this window
    // so it shares the focus grab. Faded in while an AP row is hovered; a Forget
    // button (saved nets) lives at its bottom.
    ApInfoPopup {
        id: infoPanel
        x: pop.listW + 4
        width: pop.infoW
        // Always in the scene graph; fade via opacity instead of toggling
        // `visible`. Showing/hiding an item restructures the scene graph, which
        // under the window's pointer grab disrupts hover delivery and collapses
        // the panel (oscillation). Opacity changes don't touch the scene graph.
        visible: true
        opacity: pop.showInfo ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 90
            }
        }
        theme: pop.theme
        ap: pop.hoverAp
        saved: pop.hoverSaved
        onForget: {
            if (pop.hoverAp)
                Quickshell.execDetached(["nmcli", "connection", "delete", "id", pop.hoverAp.ssid]);
            pop.hoverAp = null;
        }

        // Keeps the panel alive while the cursor is over it (incl. the Forget
        // button) -- the panel is the rows' sibling, so we track its hover here.
        HoverHandler {
            onHoveredChanged: pop.panelHover = hovered
        }
    }
}
