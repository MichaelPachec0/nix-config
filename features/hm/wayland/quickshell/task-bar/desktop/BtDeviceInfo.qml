import QtQuick
import QtQuick.Layouts

// Inline detail panel for the hovered device, rendered beside the list inside
// BluetoothPopup (faded via opacity by the parent -- mirrors ApInfoPopup). For
// the connected audio device it also shows read-only PipeWire codec/profile/
// volume and (Pixel Buds) pbpctrl per-bud battery/ANC/etc -- read from the
// shared BluetoothService (single pbpctrl owner). All read-only here; the bar
// hover panel carries the controls.
Item {
    id: info

    required property QtObject theme
    required property var bt
    property var dev: null
    property bool active: false // true while this panel is shown

    implicitWidth: 250
    implicitHeight: body.implicitHeight + 24

    // True when the hovered device is the connected audio device the service
    // polls (so its pw/pbp data applies here).
    readonly property bool isAudioDev: info.dev && info.dev.connected && info.dev.address === info.bt.audioMac
    readonly property bool isBuds: info.isAudioDev && info.bt.audioIsBuds
    readonly property bool hasPbpBattery: info.isBuds && (String(info.bt.pbp.left || "") !== "" || String(info.bt.pbp.right || "") !== "")

    // Ask the service to poll while we're showing the connected audio device.
    Binding {
        target: info.bt
        property: "menuWants"
        value: info.active && info.isAudioDev
    }

    function cap(s) {
        s = String(s || "");
        return s.length ? s.charAt(0).toUpperCase() + s.slice(1) : "";
    }

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: info.theme.bgCard
        border.width: 1
        border.color: info.theme.border

        ColumnLayout {
            id: body
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 6

            // Header: type glyph + name.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: info.bt.typeGlyph(info.dev ? info.dev.icon : "")
                    color: info.theme.textPrimary
                    font.family: info.theme.iconFont
                    font.pixelSize: 18
                }
                Text {
                    Layout.fillWidth: true
                    text: info.dev ? (info.dev.deviceName || info.dev.name || info.dev.address) : ""
                    color: info.theme.textPrimary
                    font.family: info.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            Row {
                Layout.fillWidth: true
                InfoLabel {
                    text: "Address"
                }
                InfoValue {
                    text: info.dev ? info.dev.address : ""
                }
            }
            Row {
                Layout.fillWidth: true
                InfoLabel {
                    text: "Status"
                }
                InfoValue {
                    text: !info.dev ? "" : (info.dev.connected ? "Connected" : (info.dev.paired ? "Paired" : "Available"))
                }
            }

            // Battery -- per-bud for Pixel Buds, else the BlueZ aggregate.
            Row {
                Layout.fillWidth: true
                visible: info.hasPbpBattery || (info.dev && info.dev.batteryAvailable)
                InfoLabel {
                    text: "Battery"
                }
                InfoValue {
                    text: info.hasPbpBattery ? ("L " + (info.bt.pbp.left || "?") + "%  R " + (info.bt.pbp.right || "?") + "%") : (info.dev ? Math.round(info.dev.battery * 100) + "%" : "")
                }
            }
            Row {
                Layout.fillWidth: true
                visible: info.isBuds && String(info.bt.pbp["case"] || "") !== ""
                InfoLabel {
                    text: "Case"
                }
                InfoValue {
                    text: (info.bt.pbp["case"] || "") + "%"
                }
            }

            // Audio stream (PipeWire) -- read-only.
            Row {
                Layout.fillWidth: true
                visible: info.isAudioDev && String(info.bt.pw.codec || "") !== ""
                InfoLabel {
                    text: "Codec"
                }
                InfoValue {
                    text: info.bt.pw.codec || ""
                }
            }
            Row {
                Layout.fillWidth: true
                visible: info.isAudioDev && String(info.bt.pw.profile || "") !== ""
                InfoLabel {
                    text: "Profile"
                }
                InfoValue {
                    text: info.bt.pw.profile || ""
                }
            }
            Row {
                Layout.fillWidth: true
                visible: info.isAudioDev && String(info.bt.pw.volume || "") !== ""
                InfoLabel {
                    text: "Volume"
                }
                InfoValue {
                    text: (info.bt.pw.volume || "") + "%"
                }
            }

            // Pixel Buds status (pbpctrl) -- read-only here.
            Row {
                Layout.fillWidth: true
                visible: info.isBuds && String(info.bt.pbp.anc || "") !== ""
                InfoLabel {
                    text: "ANC"
                }
                InfoValue {
                    text: info.cap(info.bt.pbp.anc)
                }
            }
            Row {
                Layout.fillWidth: true
                visible: info.isBuds && String(info.bt.pbp.multipoint || "") !== ""
                InfoLabel {
                    text: "Multipoint"
                }
                InfoValue {
                    text: info.bt.pbp.multipoint === "true" ? "On" : "Off"
                }
            }
            Row {
                Layout.fillWidth: true
                visible: info.isBuds && String(info.bt.pbp.firmware || "") !== ""
                InfoLabel {
                    text: "Firmware"
                }
                InfoValue {
                    text: info.bt.pbp.firmware || ""
                }
            }

            Row {
                Layout.fillWidth: true
                InfoLabel {
                    text: "Adapter"
                }
                InfoValue {
                    text: info.bt.adapterId
                }
            }

            // Trusted toggle.
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Trusted"
                    color: info.theme.textSecondary
                    font.family: info.theme.textFont
                    font.pixelSize: 11
                }
                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 18
                    radius: 9
                    color: (info.dev && info.dev.trusted) ? info.theme.accent : info.theme.bgItem
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                    Rectangle {
                        width: 14
                        height: 14
                        radius: 7
                        y: 2
                        x: (info.dev && info.dev.trusted) ? parent.width - width - 2 : 2
                        color: info.theme.textOnAccent
                        Behavior on x {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (info.dev)
                            info.dev.trusted = !info.dev.trusted
                    }
                }
            }

            // Forget / Unpair (only for known devices).
            Rectangle {
                Layout.fillWidth: true
                visible: info.dev && info.dev.paired
                implicitHeight: 28
                radius: 7
                color: forgetHover.hovered ? Qt.rgba(info.theme.accentRed.r, info.theme.accentRed.g, info.theme.accentRed.b, 0.18) : info.theme.bgItem
                Text {
                    anchors.centerIn: parent
                    text: "Forget device"
                    color: info.theme.accentRed
                    font.family: info.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: forgetHover
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (info.dev)
                        info.dev.forget()
                }
            }
        }
    }

    component InfoLabel: Text {
        width: 70
        color: info.theme.textSecondary
        font.family: info.theme.textFont
        font.pixelSize: 11
    }
    component InfoValue: Text {
        width: 150
        horizontalAlignment: Text.AlignRight
        color: info.theme.textPrimary
        font.family: info.theme.textFont
        font.pixelSize: 11
        elide: Text.ElideLeft
    }
}
