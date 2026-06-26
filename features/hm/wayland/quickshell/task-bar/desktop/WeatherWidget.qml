import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons

// Bar weather widget: current condition glyph + temperature, with a hover popup
// of current conditions. Data comes from lib/weather.sh (the same provider chain
// the hub card uses); the script's 30-min cache means the bar and hub share a
// single upstream fetch. Stays hidden until the first successful read.
Item {
    id: root

    required property QtObject theme
    required property var barWindow // the bar PanelWindow, for popup anchoring

    // {temp, icon, desc, source} or null before the first poll completes.
    readonly property var wx: poll.value

    visible: root.wx !== null
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    Lib.CommandPoll {
        id: poll
        interval: 1800000 // 30 min; weather.sh caches the same window
        command: ["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/weather.sh"]
        parse: function (out) {
            try {
                var d = JSON.parse(String(out));
                return {
                    temp: d.temp ?? "--",
                    icon: d.icon ?? "cloudy",
                    desc: d.desc ?? "Unknown",
                    source: d.source ?? ""
                };
            } catch (e) {
                return null;
            }
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: WeatherIcons.glyph(root.wx ? root.wx.icon : "cloudy")
            color: root.theme.weatherIcon
            font.family: root.theme.iconFont
            font.pixelSize: 14
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: (root.wx ? root.wx.temp : "--") + String.fromCodePoint(0x00B0)
            color: root.theme.textSecondary
            font.family: root.theme.textFont
            font.pixelSize: 13
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: containsMouse ? popup.show() : popup.hide()
    }

    WeatherPopup {
        id: popup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        wx: root.wx
    }
}
