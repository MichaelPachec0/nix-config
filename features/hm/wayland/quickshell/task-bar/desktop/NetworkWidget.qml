import QtQuick
import QtQuick.Layouts
import "../lib" as Lib

// Bar network widget (native nm-applet replacement, step 4a): a signal-strength
// glyph + current SSID; click opens the WiFi popup (network list / connect land
// in 4b+). Status (radio state, SSID, signal) comes from nmcli on a 5s poll.
Item {
    id: root

    required property QtObject theme
    required property var barWindow // the bar PanelWindow, for popup anchoring

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    property bool wifiEnabled: false
    property string connState: "disconnected"
    property string ssid: ""
    property int signalVal: 0

    Lib.CommandPoll {
        id: statusPoll
        interval: 5000
        command: ["bash", "-c", `
WIFI=$(nmcli -g WIFI radio 2>/dev/null || echo unknown)
echo "WIFI:$WIFI"
[ "$WIFI" != "enabled" ] && exit 0
ACTIVE=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless" && $3=="activated"{print $1; exit}')
if [ -z "$ACTIVE" ]; then
  ACT=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless" && $3=="activating"{print $1; exit}')
  [ -n "$ACT" ] && { echo "STATE:activating"; exit 0; }
  echo "STATE:disconnected"; exit 0
fi
echo "STATE:activated"
echo "SSID:$(nmcli -g 802-11-wireless.ssid connection show uuid "$ACTIVE" 2>/dev/null | head -n1)"
echo "SIGNAL:$(nmcli -g IN-USE,SIGNAL dev wifi list 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')"
`]
        parse: function (o) {
            var r = {
                enabled: false,
                state: "disconnected",
                ssid: "",
                signal: 0
            };
            String(o).split(/\r?\n/).forEach(function (line) {
                var i = line.indexOf(":");
                if (i < 0)
                    return;
                var k = line.slice(0, i);
                var v = line.slice(i + 1).trim();
                if (k === "WIFI")
                    r.enabled = (v === "enabled");
                else if (k === "STATE")
                    r.state = v;
                else if (k === "SSID")
                    r.ssid = v;
                else if (k === "SIGNAL")
                    r.signal = parseInt(v, 10) || 0;
            });
            return r;
        }
        onUpdated: {
            root.wifiEnabled = value.enabled;
            root.connState = value.state;
            root.ssid = value.ssid;
            root.signalVal = value.signal;
        }
    }

    // MDI wifi-strength glyph for the current state/level.
    function signalGlyph() {
        if (!root.wifiEnabled)
            return String.fromCodePoint(0xF092D); // off
        if (root.connState !== "activated")
            return String.fromCodePoint(0xF092F); // outline (no link)
        var s = root.signalVal;
        if (s <= 25)
            return String.fromCodePoint(0xF091F);
        if (s <= 50)
            return String.fromCodePoint(0xF0922);
        if (s <= 75)
            return String.fromCodePoint(0xF0925);
        return String.fromCodePoint(0xF0928);
    }
    function label() {
        if (!root.wifiEnabled)
            return "Off";
        if (root.connState === "activating")
            return "Connecting";
        if (root.connState !== "activated")
            return "Disconnected";
        return root.ssid || "Wi-Fi";
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5
        Text {
            text: root.signalGlyph()
            color: root.theme.textSecondary
            font.family: root.theme.iconFont
            font.pixelSize: 13
        }
        Text {
            text: root.label()
            color: root.theme.textSecondary
            font.family: root.theme.textFont
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.maximumWidth: 120
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            info.hide();
            popup.toggle();
        }
        // Hover shows the detail popup, unless the click menu is open.
        onContainsMouseChanged: {
            if (containsMouse && !popup.visible)
                info.show();
            else
                info.hide();
        }
    }

    NetworkPopup {
        id: popup
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        wifiEnabled: root.wifiEnabled
    }

    NetworkInfoPopup {
        id: info
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        ssid: root.label()
    }
}
