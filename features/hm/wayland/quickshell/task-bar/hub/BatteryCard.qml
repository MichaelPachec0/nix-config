import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

// Hub Battery card (Phase 2d, step 6): charge level + state + time remaining,
// a charge bar, and (when UPower reports it) battery health. Reads the same
// UPower.displayDevice as the bar widget. Collapses to zero height on machines
// without a laptop battery. Focused on battery only -- CPU/RAM already live in
// the header chips (surface-dots bundled them into one system card).
Rectangle {
    id: root

    required property QtObject theme

    readonly property var dev: UPower.displayDevice
    readonly property bool present: root.dev !== null && root.dev.isLaptopBattery
    readonly property real pct: root.dev ? root.dev.percentage * 100 : 0
    readonly property int state: root.dev ? root.dev.state : UPowerDeviceState.Unknown
    readonly property bool charging: root.state === UPowerDeviceState.Charging || root.state === UPowerDeviceState.FullyCharged
    // onAC reflects plugged-in even when charge-limited ("not charging").
    readonly property bool onAC: UPower.onBattery === false
    readonly property bool low: !root.onAC && root.pct <= 20
    readonly property bool healthOk: root.dev !== null && root.dev.healthSupported
    readonly property real health: root.dev ? root.dev.healthPercentage : 0
    readonly property real rateW: root.dev ? Math.abs(root.dev.changeRate) : 0

    readonly property color levelColor: root.low ? root.theme.accentRed : (root.onAC ? root.theme.accentSlider : root.theme.accent)

    function stateLabel() {
        switch (root.state) {
        case UPowerDeviceState.Charging:
            return "Charging";
        case UPowerDeviceState.Discharging:
            return "Discharging";
        case UPowerDeviceState.FullyCharged:
            return "Full";
        case UPowerDeviceState.Empty:
            return "Empty";
        case UPowerDeviceState.PendingCharge:
        case UPowerDeviceState.PendingDischarge:
            return "Not charging";
        default:
            return "Unknown";
        }
    }
    function fmtTime(s) {
        s = Math.round(s || 0);
        if (s <= 0)
            return "";
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        return h > 0 ? (h + "h " + (m < 10 ? "0" : "") + m + "m") : (m + "m");
    }
    readonly property string timeStr: {
        if (root.charging) {
            if (root.state === UPowerDeviceState.FullyCharged)
                return "";
            var tf = root.fmtTime(root.dev ? root.dev.timeToFull : 0);
            return tf ? (tf + " to full") : "";
        }
        if (root.onAC)
            return ""; // plugged in but not charging -> no "time left"
        var te = root.fmtTime(root.dev ? root.dev.timeToEmpty : 0);
        return te ? (te + " left") : "";
    }
    // MDI battery glyph: a bolt while charging, else a level-bucketed icon.
    function batGlyph() {
        if (root.onAC)
            return String.fromCodePoint(0xF0084);
        var p = root.pct;
        if (p >= 95)
            return String.fromCodePoint(0xF0079);
        if (p >= 85)
            return String.fromCodePoint(0xF0082);
        if (p >= 75)
            return String.fromCodePoint(0xF0081);
        if (p >= 65)
            return String.fromCodePoint(0xF0080);
        if (p >= 55)
            return String.fromCodePoint(0xF007F);
        if (p >= 45)
            return String.fromCodePoint(0xF007E);
        if (p >= 35)
            return String.fromCodePoint(0xF007D);
        if (p >= 25)
            return String.fromCodePoint(0xF007C);
        if (p >= 15)
            return String.fromCodePoint(0xF007B);
        if (p >= 5)
            return String.fromCodePoint(0xF007A);
        return String.fromCodePoint(0xF008E);
    }

    implicitHeight: root.present ? (col.implicitHeight + 24) : 0
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
    visible: implicitHeight > 1
    opacity: root.present ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 170
        }
    }
    clip: true

    radius: root.theme.radiusOuter
    color: root.theme.bgCard
    border.width: 1
    border.color: root.theme.border

    ColumnLayout {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 8

        // Header: label + state
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Battery"
                color: root.theme.textPrimary
                font.family: root.theme.textFont
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            Text {
                text: root.stateLabel()
                color: root.onAC ? root.theme.accentSlider : root.theme.textSecondary
                font.family: root.theme.textFont
                font.pixelSize: 11
            }
        }

        // Big glyph + percentage, time remaining on the right.
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: root.batGlyph()
                color: root.levelColor
                font.family: root.theme.iconFont
                font.pixelSize: 26
            }
            Text {
                text: Math.round(root.pct) + "%"
                color: root.theme.textPrimary
                font.family: root.theme.textFont
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            ColumnLayout {
                spacing: 1
                Layout.alignment: Qt.AlignVCenter
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.timeStr
                    visible: text !== ""
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.rateW > 0.05 ? (root.rateW.toFixed(1) + " W") : ""
                    visible: text !== ""
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                    opacity: 0.8
                }
            }
        }

        // Charge level bar.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: root.theme.bgItem
            Rectangle {
                width: Math.max(3, parent.width * Math.min(100, root.pct) / 100)
                height: parent.height
                radius: 3
                color: root.levelColor
                Behavior on width {
                    NumberAnimation {
                        duration: 250
                    }
                }
            }
        }

        // Health (only when UPower reports it).
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: root.healthOk
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Health"
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: Math.round(root.health) + "%"
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 5
                radius: 2
                color: root.theme.bgItem
                Rectangle {
                    width: Math.max(3, parent.width * Math.min(100, root.health) / 100)
                    height: parent.height
                    radius: 2
                    color: Qt.rgba(root.theme.accentSlider.r, root.theme.accentSlider.g, root.theme.accentSlider.b, 0.6)
                }
            }
        }
    }
}
