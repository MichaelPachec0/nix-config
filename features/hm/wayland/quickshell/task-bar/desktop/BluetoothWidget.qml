import QtQuick
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
            return c[0].deviceName || c[0].name || c[0].address;
        if (c.length > 1)
            return c.length + " devices";
        return "";
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.stateGlyph()
            font.family: root.theme.iconFont
            font.pixelSize: 13
            color: root.connectedCount > 0 ? root.theme.accent : root.theme.textSecondary
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 120
            visible: text.length > 0
            text: root.label()
            font.family: root.theme.textFont
            font.pixelSize: 11
            color: root.theme.textSecondary
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            info.hide();
            menu.toggle();
        }
        onContainsMouseChanged: {
            if (containsMouse && !menu.visible)
                info.show();
            else
                info.hide();
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
