import QtQuick
import "../lib" as Lib
import QtQuick.Layouts

// Bar Bluetooth widget: a state glyph + the connected device name. Mirrors
// WifiWidget. Backed by the shared BluetoothService (native Quickshell.Bluetooth)
// -- reactive, no poll. Click opens the device menu; hover tooltip wired later.
Item {
    id: root

    required property QtObject theme
    required property var barWindow
    required property var bt // Lib.BluetoothService

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    readonly property int connectedCount: root.bt ? root.bt.connectedDevices.length : 0

    // Compact tags for known devices, matched case-insensitively as a substring
    // so any owner prefix ("<name>'s Pixel Buds Pro 2") still resolves.
    readonly property var nameAliases: [
        { match: "pixel buds", short: "PBP2" }
    ]
    function shortName(name) {
        if (!name)
            return name;
        var lower = name.toLowerCase();
        for (var i = 0; i < root.nameAliases.length; i++) {
            if (lower.indexOf(root.nameAliases[i].match) >= 0)
                return root.nameAliases[i].short;
        }
        return name;
    }

    function stateGlyph() {
        if (!root.bt || !root.bt.available || !root.bt.enabled || root.bt.blocked)
            return String.fromCodePoint(0xF00B2); // bluetooth-off
        if (root.connectedCount > 0)
            return String.fromCodePoint(0xF00B1); // bluetooth-connect
        return String.fromCodePoint(0xF00AF); // bluetooth
    }
    function label() {
        if (!root.bt || !root.bt.available || !root.bt.enabled)
            return "";
        var c = root.bt.connectedDevices;
        if (c.length === 1)
            return root.shortName(c[0].deviceName || c[0].name || c[0].address);
        if (c.length > 1)
            return c.length + " devices";
        return "";
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 6

        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            text: root.stateGlyph()
            font.family: root.theme.iconFont
            font.pixelSize: 13
            color: root.connectedCount > 0 ? root.theme.accent : root.theme.textSecondary
        }
        // Device name: adapt the Wi-Fi/media marquee -- clip to ~8 chars and
        // ping-pong scroll on hover when the name overflows, instead of eliding.
        // The icon font is monospace, so 8 chars of it is the cap width. Short
        // aliases (e.g. "PBP2") stay static; long names scroll on hover.
        TextMetrics {
            id: capMetrics
            font.family: root.theme.iconFont
            font.pixelSize: 11
            text: "MMMMMMMM" // 8 chars
        }
        Item {
            id: marquee
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.min(btLabel.implicitWidth, capMetrics.advanceWidth)
            Layout.preferredHeight: 24
            visible: btLabel.text.length > 0
            clip: true

            readonly property real scrollDist: Math.max(0, btLabel.implicitWidth - marquee.width)
            readonly property bool overflow: marquee.scrollDist > 0
            // ms per pixel: higher = slower. ~11 px/s.
            readonly property int scrollDur: Math.max(2000, marquee.scrollDist * 90)

            Lib.BarText {
                id: btLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.label()
                font.family: root.theme.iconFont
                font.pixelSize: 11
                color: root.theme.textPrimary
                onTextChanged: x = 0
            }

            SequentialAnimation {
                running: marquee.overflow && hover.containsMouse
                loops: Animation.Infinite
                onRunningChanged: if (!running)
                    btLabel.x = 0
                PauseAnimation {
                    duration: 1400
                }
                NumberAnimation {
                    target: btLabel
                    property: "x"
                    from: 0
                    to: -marquee.scrollDist
                    duration: marquee.scrollDur
                    easing.type: Easing.InOutQuad
                }
                PauseAnimation {
                    duration: 1400
                }
                NumberAnimation {
                    target: btLabel
                    property: "x"
                    from: -marquee.scrollDist
                    to: 0
                    duration: marquee.scrollDur
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            info.iconHovered = false;
            info.hide();
            menu.toggle();
        }
        onContainsMouseChanged: {
            if (containsMouse && !menu.visible) {
                info.iconHovered = true;
                info.show();
            } else {
                info.iconHovered = false;
            }
        }
    }

    BluetoothPopup {
        id: menu
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        bt: root.bt
    }
    BtInfoPopup {
        id: info
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        bt: root.bt
    }
}
