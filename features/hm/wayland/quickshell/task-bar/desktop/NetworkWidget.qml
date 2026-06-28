import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib

// Bar network widget (nm-applet replacement): a state glyph (Wi-Fi strength or
// Ethernet), the current identifier, and -- when a VPN is up -- a shield. The
// glyph is tinted by NM connectivity (green full / orange limited / yellow
// portal / red none). Left-click opens the popup; right-click cycles the label
// (Wi-Fi SSID>BSSID>IP, wired Name>IP); middle-click copies the shown value.
Item {
    id: root

    required property QtObject theme
    required property var barWindow

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    property int displayMode: 0
    property bool copiedFlash: false

    Lib.NetworkService {
        id: net
    }

    // Cycle modes per connection type (BSSID is Wi-Fi only).
    function modes() {
        return net.primaryType === "ethernet" ? ["name", "ip"] : ["ssid", "bssid", "ip"];
    }
    function shownValue() {
        var m = root.modes()[root.displayMode % root.modes().length];
        if (m === "ssid")
            return net.ssid;
        if (m === "bssid")
            return net.bssid;
        if (m === "ip")
            return net.ip;
        if (m === "name")
            return net.connName || net.iface;
        return "";
    }

    function stateGlyph() {
        if (net.primaryType === "ethernet")
            return String.fromCodePoint(net.connState === "activated" ? 0xF0200 : 0xF0202);
        if (!net.wifiRadio)
            return String.fromCodePoint(0xF092D); // wifi off
        if (net.connState !== "activated")
            return String.fromCodePoint(0xF092F); // outline, no link
        var s = net.signalVal;
        if (s <= 25)
            return String.fromCodePoint(0xF091F);
        if (s <= 50)
            return String.fromCodePoint(0xF0922);
        if (s <= 75)
            return String.fromCodePoint(0xF0925);
        return String.fromCodePoint(0xF0928);
    }
    // Connectivity tint, only while actually connected.
    function glyphColor() {
        if (net.connState !== "activated")
            return root.theme.textSecondary;
        switch (net.connectivity) {
        case "full":
            return root.theme.accentGreen;
        case "limited":
            return root.theme.accentOrange;
        case "portal":
            return root.theme.accentYellow;
        case "none":
            return root.theme.accentRed;
        default:
            return root.theme.textSecondary;
        }
    }
    function label() {
        if (root.copiedFlash)
            return "Copied";
        if (!net.wifiRadio && net.primaryType !== "ethernet")
            return "Off";
        if (net.connState === "activating")
            return "Connecting";
        if (net.connState !== "activated")
            return "Disconnected";
        return root.shownValue() || (net.primaryType === "ethernet" ? "Wired" : "Wi-Fi");
    }

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: root.copiedFlash = false
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5
        Text {
            text: root.stateGlyph()
            color: root.glyphColor()
            font.family: root.theme.iconFont
            font.pixelSize: 13
        }
        Text {
            text: root.label()
            color: root.theme.textSecondary
            font.family: root.theme.textFont
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.maximumWidth: 160
        }
        // VPN shield, only when a VPN is up.
        // Codepoint F099D (shield-lock); F0582 verified as ornamental knot, swapped.
        Text {
            visible: net.vpnActive
            text: String.fromCodePoint(0xF099D) // shield-lock vpn
            color: root.theme.accentGreen
            font.family: root.theme.iconFont
            font.pixelSize: 12
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                root.displayMode = (root.displayMode + 1) % root.modes().length;
            } else if (mouse.button === Qt.MiddleButton) {
                var v = root.shownValue();
                if (v) {
                    // stdin pipe so a value starting with '-' isn't parsed as a flag
                    Quickshell.execDetached(["bash", "-lc", "printf '%s' \"$1\" | wl-copy", "_", v]);
                    root.copiedFlash = true;
                    copiedTimer.restart();
                }
            } else {
                info.hide();
                popup.toggle();
            }
        }
        onContainsMouseChanged: {
            if (containsMouse && !popup.visible)
                info.show();
            else
                info.hide();
        }
    }

    // Tasks 6/7 will add net: net; for now pass the existing props the popups accept.
    NetworkPopup {
        id: popup
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        wifiEnabled: net.wifiRadio
    }

    NetworkInfoPopup {
        id: info
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        ssid: root.label()
    }
}
