import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Bluetooth device menu. Mirrors WifiPopup: a grabFocus PopupWindow of FIXED
// size (listW + 4 + infoW) so the detail panel's space is always reserved and
// the list never re-centers; pinned-left Bottom|Right gravity. Header carries
// the power + discovery toggles. Device sections + detail panel are added in
// later tasks.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var bt // Lib.BluetoothService

    property var hoverDev: null // device the pointer is over (for the detail panel)

    // Hover debounce across the list<->panel gap (mirrors WifiPopup): the panel
    // fades out only after the pointer has left both for 180ms.
    property bool listHover: false
    property bool panelHover: false
    readonly property bool overMenu: pop.listHover || pop.panelHover
    property bool showInfo: false
    onOverMenuChanged: {
        if (pop.overMenu) {
            collapseTimer.stop();
            if (pop.hoverDev)
                pop.showInfo = true;
        } else {
            collapseTimer.restart();
        }
    }
    property Timer collapseTimer: Timer {
        interval: 180
        onTriggered: pop.showInfo = false
    }

    readonly property int listW: 280
    readonly property int infoW: 250

    implicitWidth: pop.listW + 4 + pop.infoW
    implicitHeight: Math.max(card.implicitHeight, 260)
    color: "transparent"
    visible: false
    grabFocus: true

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right // pin left edge, grow rightward

    // Open with the list's left edge at `px` (bar-window coordinates).
    function openAt(px) {
        pop.anchor.rect.x = px;
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }
    function toggle() {
        if (pop.visible) {
            pop.close();
            return;
        }
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.openAt(x - pop.listW / 2); // center the LIST under the icon
    }
    function close() {
        if (!pop.visible)
            return;
        pop.bt.setDiscovering(false); // never leave the radio scanning
        pop.visible = false;
    }
    property string actionError: ""
    property Timer errorTimer: Timer {
        interval: 4000
        onTriggered: pop.actionError = ""
    }
    function showError(msg) {
        pop.actionError = msg;
        pop.errorTimer.restart();
    }
    function onDeviceClicked(dev) {
        if (!dev)
            return;
        pop.actionError = "";
        try {
            if (dev.connected)
                dev.disconnect();
            else if (dev.paired)
                dev.connect();
            else
                pop.bt.pairAndConnect(dev);
        } catch (e) {
            pop.showError("Action failed");
        }
    }

    Rectangle {
        id: card
        width: pop.listW
        x: 0
        implicitHeight: col.implicitHeight + 20
        radius: 11
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        focus: true
        Keys.onEscapePressed: pop.close()

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

            // --- Header: title + discovery toggle + power toggle -------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Bluetooth"
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                // Discovery toggle (scan). Pulses subtly while discovering.
                Rectangle {
                    id: scanBtn
                    visible: pop.bt.enabled
                    implicitWidth: 26
                    implicitHeight: 22
                    radius: 7
                    Layout.alignment: Qt.AlignVCenter
                    color: scanHover.hovered ? pop.theme.bgItemHover : pop.theme.bgItem
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF0349) // magnify (scan)
                        font.family: pop.theme.iconFont
                        font.pixelSize: 13
                        color: pop.bt.discovering ? pop.theme.accent : pop.theme.textSecondary
                        SequentialAnimation on opacity {
                            running: pop.bt.discovering
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 0.35
                                duration: 600
                            }
                            NumberAnimation {
                                to: 1.0
                                duration: 600
                            }
                        }
                    }
                    HoverHandler {
                        id: scanHover
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.bt.setDiscovering(!pop.bt.discovering)
                    }
                }

                // Power toggle pill (mirror WifiPopup's animated pill).
                Rectangle {
                    id: pill
                    implicitWidth: 34
                    implicitHeight: 18
                    radius: 9
                    Layout.alignment: Qt.AlignVCenter
                    color: pop.bt.enabled ? pop.theme.accent : pop.theme.bgItem
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                    Rectangle {
                        id: knob
                        width: 14
                        height: 14
                        radius: 7
                        y: 2
                        x: pop.bt.enabled ? parent.width - width - 2 : 2
                        color: pop.theme.textOnAccent
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
                        onClicked: pop.bt.setEnabled(!pop.bt.enabled)
                    }
                }
            }

            // "Bluetooth is off" message.
            Text {
                Layout.fillWidth: true
                visible: !pop.bt.enabled
                text: !pop.bt.available ? "No Bluetooth adapter" : (pop.bt.blocked ? "Bluetooth blocked (rfkill)" : "Bluetooth is off")
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 12
                topPadding: 6
                bottomPadding: 6
            }

            // Transient error from a failed connect/pair action.
            Text {
                Layout.fillWidth: true
                visible: pop.actionError.length > 0
                text: pop.actionError
                color: pop.theme.accentRed
                font.family: pop.theme.textFont
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            // --- Device sections (only while powered) -----------------------
            Section {
                title: "Connected"
                devices: pop.bt.connectedDevices
                visible: pop.bt.enabled && pop.bt.connectedDevices.length > 0
            }
            Section {
                title: "Paired"
                devices: pop.bt.pairedDevices
                visible: pop.bt.enabled && pop.bt.pairedDevices.length > 0
            }
            // Discovered devices, split: those broadcasting a name vs the rest.
            Section {
                title: "Available"
                devices: pop.bt.discoveredNamed
                scroll: true
                maxH: 200
                visible: pop.bt.enabled && pop.bt.discovering && pop.bt.discoveredNamed.length > 0
            }
            Section {
                title: "Unnamed"
                devices: pop.bt.discoveredUnnamed
                scroll: true
                maxH: 150
                visible: pop.bt.enabled && pop.bt.discovering && pop.bt.discoveredUnnamed.length > 0
            }
            // Empty hint when powered but nothing to show.
            Text {
                Layout.fillWidth: true
                visible: pop.bt.enabled && pop.bt.connectedDevices.length === 0 && pop.bt.pairedDevices.length === 0 && !(pop.bt.discovering && pop.bt.discoveredDevices.length > 0)
                text: pop.bt.discovering ? "Scanning..." : "No devices. Toggle scan to discover."
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 12
                topPadding: 4
                bottomPadding: 4
            }
        }
    }

    BtDeviceInfo {
        x: pop.listW + 4
        width: pop.infoW
        theme: pop.theme
        bt: pop.bt
        dev: pop.hoverDev
        opacity: pop.showInfo ? 1 : 0
        visible: true // never toggle visible under the grab; fade only
        Behavior on opacity {
            NumberAnimation {
                duration: 90
            }
        }
        HoverHandler {
            onHoveredChanged: pop.panelHover = hovered
        }
    }

    // A titled list of device rows. `scroll` caps height and adds a thin bar.
    component Section: ColumnLayout {
        id: sec
        property string title: ""
        property var devices: []
        property bool scroll: false
        property int maxH: 240
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: sec.title
            color: pop.theme.textSecondary
            font.family: pop.theme.textFont
            font.pixelSize: 10
            font.weight: Font.Bold
        }
        ListView {
            id: lv
            Layout.fillWidth: true
            interactive: sec.scroll
            clip: sec.scroll
            Layout.preferredHeight: sec.scroll ? Math.min(contentHeight, sec.maxH) : contentHeight
            model: sec.devices
            delegate: DeviceRow {
                required property var modelData
                width: lv.width
                dev: modelData
            }
            ScrollBar.vertical: ScrollBar {
                policy: lv.contentHeight > lv.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                width: 6
                contentItem: Rectangle {
                    radius: 3
                    color: pop.theme.bgItemHover
                }
            }
        }
    }

    // One device row: type glyph + name + battery + connecting spinner + check.
    component DeviceRow: Rectangle {
        id: drow
        property var dev: null
        height: 30
        radius: 6
        color: rowHover.hovered ? pop.theme.bgItemHover : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 10
            spacing: 8

            Text {
                text: pop.bt.typeGlyph(drow.dev ? drow.dev.icon : "")
                color: (drow.dev && drow.dev.connected) ? pop.theme.accent : pop.theme.textSecondary
                font.family: pop.theme.iconFont
                font.pixelSize: 16
            }
            Text {
                Layout.fillWidth: true
                text: drow.dev ? (drow.dev.deviceName || drow.dev.name || drow.dev.address) : ""
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text {
                visible: drow.dev && drow.dev.batteryAvailable
                text: drow.dev ? Math.round(drow.dev.battery * 100) + "%" : ""
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 11
            }
            Text {
                // Busy indicator while connecting/disconnecting or pairing.
                visible: drow.dev && (drow.dev.pairing || drow.dev.state === BluetoothDeviceState.Connecting || drow.dev.state === BluetoothDeviceState.Disconnecting)
                text: String.fromCodePoint(0xF01D9) // dots (busy)
                color: pop.theme.textSecondary
                font.family: pop.theme.iconFont
                font.pixelSize: 14
            }
            Text {
                visible: drow.dev && drow.dev.connected
                text: String.fromCodePoint(0xF012C) // check
                color: pop.theme.accent
                font.family: pop.theme.iconFont
                font.pixelSize: 14
            }
        }
        HoverHandler {
            id: rowHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                pop.hoverDev = drow.dev
        }
        TapHandler {
            onTapped: pop.onDeviceClicked(drow.dev)
        }
    }
}
