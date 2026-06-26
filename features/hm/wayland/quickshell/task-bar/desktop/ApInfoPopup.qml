import QtQuick
import QtQuick.Layouts
import Quickshell

// Per-AP detail panel, shown inside the WiFi menu window (to the right of the
// list) so it lives within the menu's focus grab -- a separate popup window
// never receives hover/clicks while the menu holds the grab. Mirrors the
// connected-AP popup; saved networks get a "Forget network" button below.
Item {
    id: root

    required property QtObject theme
    property var ap: null
    property bool saved: false

    signal forget

    implicitWidth: 250
    implicitHeight: content.implicitHeight

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
    function channelStr(a) {
        if (!a.chan)
            return "N/A";
        var w = a.bandwidth ? ", " + String(a.bandwidth).replace(/\s/g, "") : "";
        return a.chan + " (" + root.band(a.freq) + ": " + (a.freq || "?") + "MHz" + w + ")";
    }
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

    readonly property var rows: {
        var a = root.ap || {};
        return [
            {
                k: "Signal",
                v: (a.signal !== undefined ? (a.signal + "%" + (a.dbm !== undefined ? " (" + a.dbm + " dBm)" : "")) : "N/A")
            },
            {
                k: "Channel",
                v: root.channelStr(a)
            },
            {
                k: "Security",
                v: root.decodeSec(a)
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
                v: root.phyFromRate(a.rate)
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

    Column {
        id: content
        width: parent.width
        spacing: 4

        Rectangle {
            width: parent.width
            implicitHeight: col.implicitHeight + 16
            radius: 11
            color: root.theme.bgCard
            border.width: 1
            border.color: root.theme.border

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
                    text: (root.ap && root.ap.ssid) ? root.ap.ssid : "Wi-Fi"
                    color: root.theme.textPrimary
                    font.family: root.theme.textFont
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Repeater {
                    model: root.rows
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            text: modelData.k
                            color: root.theme.textSecondary
                            font.family: root.theme.textFont
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: modelData.v
                            color: root.theme.textPrimary
                            font.family: root.theme.textFont
                            font.pixelSize: 11
                            elide: Text.ElideLeft
                        }
                    }
                }
            }
        }

        // Forget button (saved networks only), 4px below the card.
        Rectangle {
            visible: root.saved
            width: parent.width
            implicitHeight: 30
            radius: 11
            color: forgetHover.hovered ? root.theme.accentRed : root.theme.bgCard
            border.width: 1
            border.color: forgetHover.hovered ? root.theme.accentRed : root.theme.border
            Behavior on color {
                ColorAnimation {
                    duration: 120
                }
            }
            Text {
                anchors.centerIn: parent
                text: "Forget network"
                color: forgetHover.hovered ? root.theme.textOnAccent : root.theme.accentRed
                font.family: root.theme.textFont
                font.pixelSize: 12
            }
            HoverHandler {
                id: forgetHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.forget()
            }
        }
    }
}
