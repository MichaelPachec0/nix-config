import QtQuick
import QtQuick.Layouts
import Quickshell

// Per-AP detail tooltip, shown beside the network menu when a row is hovered.
// Mirrors the connected-AP popup but for any scanned AP: signal, channel,
// encryption, BSSID, advertised rate, PHY. All data comes from the scan row
// (nmcli); PHY is derived from the advertised max rate (no per-scanned-AP PHY
// on D-Bus), so it is approximate. grabFocus is off -- it is just a tooltip.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var menuWindow // the WifiPopup, anchored flush to its right
    property var ap: null

    implicitWidth: 250
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: false

    // Anchor to the menu window's right edge (no coord math). rect width +4
    // adds a 4px x gap; Right|Bottom gravity top-aligns it with the menu.
    anchor.window: pop.menuWindow
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: pop.menuWindow ? pop.menuWindow.width + 4 : 0
    anchor.rect.height: 0
    anchor.edges: Edges.Right
    anchor.gravity: Edges.Right | Edges.Bottom

    function band(f) {
        f = f || 0;
        return f >= 5955 ? "6G" : (f >= 5000 ? "5G" : "2.4G");
    }
    function phyFromRate(rate) {
        var n = parseInt(String(rate), 10) || 0;
        if (n <= 0)
            return "N/A";
        if (n <= 54)
            return "802.11a/g";
        if (n <= 300)
            return "802.11n";
        if (n <= 866)
            return "802.11ac";
        return "802.11ax";
    }
    // "36 (5G: 5180MHz, 80MHz)" -- channel + band + freq + width (nmcli BANDWIDTH).
    function channelStr(a) {
        if (!a.chan)
            return "N/A";
        var w = a.bandwidth ? ", " + String(a.bandwidth).replace(/\s/g, "") : "";
        return a.chan + " (" + pop.band(a.freq) + ": " + (a.freq || "?") + "MHz" + w + ")";
    }
    // nmcli RSN-FLAGS, e.g. "pair_ccmp group_ccmp psk sae" -> "WPA2/WPA3 (CCMP)".
    function decodeSec(a) {
        var f = String(a.rsn || "").toLowerCase();
        if (!a.secured || f === "" || f === "(none)")
            return "Open";
        var mgmt = [];
        if (f.indexOf("sae") >= 0)
            mgmt.push("WPA3");
        if (f.indexOf("psk") >= 0)
            mgmt.push("WPA2");
        if (f.indexOf("802_1x") >= 0 || f.indexOf("eap") >= 0)
            mgmt.push("Enterprise");
        if (f.indexOf("owe") >= 0)
            mgmt.push("OWE");
        if (mgmt.length === 0)
            mgmt.push("WPA");
        var c = f.indexOf("ccmp") >= 0 ? "CCMP" : (f.indexOf("gcmp") >= 0 ? "GCMP" : (f.indexOf("tkip") >= 0 ? "TKIP" : ""));
        return mgmt.join("/") + (c ? " (" + c + ")" : "");
    }

    function showFor(ap) {
        pop.ap = ap;
        pop.visible = true;
    }
    function hide() {
        pop.visible = false;
    }

    readonly property var rows: {
        var a = pop.ap || {};
        return [
            {
                k: "Signal",
                v: (a.signal !== undefined ? (a.signal + "%" + (a.dbm !== undefined ? " (" + a.dbm + " dBm)" : "")) : "N/A")
            },
            {
                k: "Channel",
                v: pop.channelStr(a)
            },
            {
                k: "Security",
                v: pop.decodeSec(a)
            },
            {
                k: "BSSID",
                v: (a.bssid || "N/A")
            },
            {
                k: "Rate",
                v: (a.rate || "N/A")
            },
            {
                k: "PHY",
                v: pop.phyFromRate(a.rate)
            },
            {
                k: "Mode",
                v: (a.mode || "N/A")
            },
            {
                k: "Seen",
                v: (a.age !== undefined ? a.age + "s ago" : "N/A")
            }
        ];
    }

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 16
        radius: 11
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 5

            Text {
                Layout.fillWidth: true
                text: (pop.ap && pop.ap.ssid) ? pop.ap.ssid : "Wi-Fi"
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 12
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            Repeater {
                model: pop.rows
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: modelData.k
                        color: pop.theme.textSecondary
                        font.family: pop.theme.textFont
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.v
                        color: pop.theme.textPrimary
                        font.family: pop.theme.textFont
                        font.pixelSize: 11
                        elide: Text.ElideLeft
                    }
                }
            }
        }
    }
}
