import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons
import "../lib/locations.js" as Locations

// Bar weather widget: current condition glyph + temperature for the selected
// location, with an interactive hover popup (detail + forecast + location
// chips). Data comes from lib/weather.sh for the active location (shared
// weatherState.selectedId); the script's per-location cache means the bar and
// hub share one upstream fetch. Stays hidden until the first successful read.
Item {
    id: root

    required property QtObject theme
    required property var barWindow // the bar PanelWindow, for popup anchoring
    required property var weatherState

    readonly property var loc: Locations.byId(root.weatherState.selectedId)
    // {temp, icon, desc, source, feels, humidity, wind, windDir, place, forecast[]}
    readonly property var wx: poll.value

    visible: root.wx !== null
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    // Refetch immediately when the location changes (after the command binding
    // updates this tick).
    onLocChanged: Qt.callLater(poll.poll)

    Lib.CommandPoll {
        id: poll
        interval: 1800000 // 30 min; weather.sh caches the same window
        command: ["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/weather.sh " + Locations.argsFor(root.loc)]
        parse: function (out) {
            try {
                var d = JSON.parse(String(out));
                return {
                    temp: d.temp ?? "--",
                    icon: d.icon ?? "cloudy",
                    desc: d.desc ?? "Unknown",
                    source: d.source ?? "",
                    feels: d.feels ?? "",
                    humidity: d.humidity ?? "",
                    wind: d.wind ?? "",
                    windDir: d.windDir ?? "",
                    place: d.place ?? "",
                    forecast: d.forecast ?? []
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

    // Hover persistence: keep the popup open while the cursor is over the widget
    // OR the popup itself, so chips inside the popup are clickable.
    HoverHandler {
        id: widgetHover
    }
    readonly property bool over: widgetHover.hovered || popup.contentHovered
    onOverChanged: {
        if (root.over) {
            hideTimer.stop();
            popup.show();
        } else {
            hideTimer.restart();
        }
    }
    Timer {
        id: hideTimer
        interval: 250
        onTriggered: if (!root.over)
            popup.hide()
    }

    WeatherPopup {
        id: popup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        wx: root.wx
        weatherState: root.weatherState
    }
}
