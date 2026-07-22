import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../lib" as Lib

// Battery detail popup shown on hover over the bar battery widget. Read-only, so
// it's a plain non-grab tooltip. The header is reactive (UPower.displayDevice +
// UPower.onBattery); the detail rows come from a `upower -i` poll while visible,
// which exposes everything UPower knows (energy/design, voltage, charge cycles,
// technology, charge-limit thresholds, vendor/model/serial). UPower is
// world-readable on the system bus, so no extra D-Bus permissions are needed.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    property var powerz: null   // shared PowerZStats; popupOpen gates its poll

    readonly property var dev: UPower.displayDevice
    readonly property real pct: pop.dev ? pop.dev.percentage * 100 : 0
    readonly property int devState: pop.dev ? pop.dev.state : UPowerDeviceState.Unknown
    readonly property bool onAC: UPower.onBattery === false
    readonly property bool low: !pop.onAC && pop.pct <= 20
    readonly property color levelColor: pop.low ? pop.theme.accentRed : (pop.onAC ? pop.theme.accentSlider : pop.theme.accent)

    implicitWidth: 260
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: false

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function show() {
        if (pop.visible)
            return;
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
        if (pop.powerz)
            pop.powerz.popupOpen = true;
    }
    function hide() {
        pop.visible = false;
        if (pop.powerz)
            pop.powerz.popupOpen = false;
    }

    function stateLabel() {
        switch (pop.devState) {
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
    function batGlyph() {
        if (pop.onAC)
            return String.fromCodePoint(0xF0084); // charging/AC
        var p = pop.pct;
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

    // Everything UPower exposes for the battery, parsed from `upower -i`.
    property var info: ({})
    Lib.CommandPoll {
        interval: 2000
        running: pop.visible
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/battery-info.sh"]
        parse: function (out) {
            var m = {};
            String(out || "").split("\n").forEach(function (line) {
                var i = line.indexOf(":");
                if (i < 0)
                    return;
                var k = line.slice(0, i).trim().toLowerCase();
                var v = line.slice(i + 1).trim();
                if (k && v)
                    m[k] = v;
            });
            return m;
        }
        onUpdated: pop.info = value
    }

    function cap(s) {
        s = String(s || "");
        return s.length ? s.charAt(0).toUpperCase() + s.slice(1) : s;
    }

    // Comprehensive detail rows (skip whatever isn't reported).
    readonly property var rows: {
        var i = pop.info || {};
        var r = [];
        r.push({
            k: "Power source",
            v: pop.onAC ? "AC" : "Battery"
        });
        if (i["state"])
            r.push({
                k: "State",
                v: pop.cap(i["state"]).replace("-", " ")
            });
        if (i["time to full"])
            r.push({
                k: "Time to full",
                v: i["time to full"]
            });
        if (i["time to empty"])
            r.push({
                k: "Time to empty",
                v: i["time to empty"]
            });
        if (i["energy-rate"])
            r.push({
                k: "Power draw",
                v: i["energy-rate"]
            });
        if (i["charge-threshold-supported"] === "yes" && i["charge-start-threshold"])
            r.push({
                k: "Charge limit",
                v: i["charge-start-threshold"] + " - " + (i["charge-end-threshold"] || "?")
            });
        if (i["capacity"])
            r.push({
                k: "Health",
                v: i["capacity"]
            });
        if (i["energy"] && i["energy-full"])
            r.push({
                k: "Energy",
                v: i["energy"] + " / " + i["energy-full"]
            });
        if (i["energy-full-design"])
            r.push({
                k: "Design",
                v: i["energy-full-design"]
            });
        if (i["voltage"])
            r.push({
                k: "Voltage",
                v: i["voltage"]
            });
        if (i["charge-cycles"] && i["charge-cycles"] !== "N/A")
            r.push({
                k: "Cycles",
                v: i["charge-cycles"]
            });
        if (i["technology"])
            r.push({
                k: "Technology",
                v: pop.cap(i["technology"]).replace("-", " ")
            });
        if (i["warning-level"] && i["warning-level"] !== "none")
            r.push({
                k: "Warning",
                v: pop.cap(i["warning-level"])
            });
        if (i["vendor"])
            r.push({
                k: "Vendor",
                v: i["vendor"]
            });
        if (i["model"])
            r.push({
                k: "Model",
                v: i["model"]
            });
        if (i["serial"])
            r.push({
                k: "Serial",
                v: i["serial"]
            });
        if (i["native-path"])
            r.push({
                k: "Path",
                v: i["native-path"]
            });
        return r;
    }

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            // Header: glyph + big % + state
            RowLayout {
                Layout.fillWidth: true
                spacing: 9
                Text {
                    text: pop.batGlyph()
                    color: pop.levelColor
                    font.family: pop.theme.iconFont
                    font.pixelSize: 22
                }
                Text {
                    text: Math.round(pop.pct) + "%"
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: pop.stateLabel()
                    color: pop.onAC ? pop.theme.accentSlider : pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 11
                }
            }

            // Charge bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: pop.theme.bgItem
                Rectangle {
                    width: Math.max(3, parent.width * Math.min(100, pop.pct) / 100)
                    height: parent.height
                    radius: 3
                    color: pop.levelColor
                }
            }

            // Detail rows
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
                        elide: Text.ElideRight
                    }
                }
            }

            // --- POWER-Z USB meter (KM003C) ------------------------------------
            // Shown while the meter is present (active) or claimed by another app
            // (busy); hidden entirely when unplugged (absent). Read-only sysfs via
            // the shared PowerZStats provider -- never locks the device.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                visible: pop.powerz && pop.powerz.state !== "absent"

                Text {
                    text: "USB Meter"
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                // busy: another app owns interface 1.0 (hwmon detached).
                Text {
                    visible: pop.powerz && pop.powerz.state === "busy"
                    Layout.fillWidth: true
                    text: "In use by another app"
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 11
                }

                // active: live readings.
                Repeater {
                    model: (pop.powerz && pop.powerz.state === "active") ? [
                        { k: "VBUS", v: pop.powerz.vbus.toFixed(2) + " V" },
                        { k: "IBUS", v: pop.powerz.ibus.toFixed(2) + " A" },
                        { k: "Power", v: pop.powerz.power.toFixed(1) + " W" },
                        { k: "CC1", v: pop.powerz.cc1.toFixed(2) + " V" },
                        { k: "CC2", v: pop.powerz.cc2.toFixed(2) + " V" }
                    ] : []
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
                        }
                    }
                }
            }
        }
    }
}
