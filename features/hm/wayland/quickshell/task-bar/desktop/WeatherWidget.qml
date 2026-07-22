import QtQuick
import QtQuick.Layouts
import Quickshell
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

    // --- alert state: pulse the widget when today's weather is notable --------
    // Heat is read off the current temperature (>=85 orange, >=90 red); rain off
    // today's forecast (or a current rainy condition) -> blue. Heat wins.
    function isRainy(k) {
        return k === "rain" || k === "showers" || k === "drizzle" || k === "thunder";
    }
    readonly property int curTemp: (root.wx && root.wx.temp) ? (parseInt(root.wx.temp) || 0) : 0
    readonly property var today: (root.wx && root.wx.forecast && root.wx.forecast.length > 0) ? root.wx.forecast[0] : null
    readonly property bool rainToday: (root.today && root.isRainy(root.today.icon)) || (root.wx ? root.isRainy(root.wx.icon) : false)
    // Only the CURRENT location pulses the bar pill. A heat/rain (or any) alert
    // for a manually-selected remote city (LA/SF/NYC/Durango) isn't where the
    // user physically is, so it must never highlight the pill -- the popup still
    // surfaces that city's own alerts when it's open.
    readonly property bool isCurrentPlace: root.loc ? (root.loc.geo === true) : false
    readonly property string alert: {
        if (!root.isCurrentPlace)
            return "";
        if (root.curTemp >= 90)
            return "red";
        if (root.curTemp >= 85)
            return "orange";
        if (root.rainToday)
            return "blue";
        return "";
    }
    // Alert hues: red/orange from the theme; a clear blue for rain (the theme's
    // accentBlue reads too teal against the green widgets to signal "rain").
    readonly property color alertColor: root.alert === "red" ? root.theme.accentRed : root.alert === "orange" ? root.theme.accentSlider2 : root.alert === "blue" ? "#4d8fd6" : "transparent"

    visible: root.wx !== null
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    // Refetch immediately when the location changes (after the command binding
    // updates this tick).
    onLocChanged: Qt.callLater(poll.poll)

    Lib.CommandPoll {
        id: poll
        interval: 1800000 // 30 min; weather.sh caches the same window
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/weather.sh"].concat(Locations.argsArrayFor(root.loc))
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
                    precip: d.precip ?? "",
                    wind: d.wind ?? "",
                    windDir: d.windDir ?? "",
                    place: d.place ?? "",
                    forecast: d.forecast ?? [],
                    hourly: d.hourly ?? [],
                    uv: d.uv ?? "",
                    windGust: d.windGust ?? "",
                    precipType: d.precipType ?? "",
                    sunrise: d.sunrise ?? "",
                    sunset: d.sunset ?? "",
                    alerts: d.alerts ?? []
                };
            } catch (e) {
                return null;
            }
        }
    }

    // The alert pulse itself is rendered by the enclosing Lib.Pill (bound to
    // root.alert / root.alertColor in the taskbar) so the colour fills the whole
    // capsule uniformly instead of a rectangle behind just this content.

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5

        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            text: WeatherIcons.glyph(root.wx ? root.wx.icon : "cloudy")
            color: root.theme.weatherIcon
            font.family: root.theme.iconFont
            font.pixelSize: 13
        }
        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            text: (root.wx ? root.wx.temp : "--") + String.fromCodePoint(0x00B0)
            color: root.theme.textPrimary
            font.family: root.theme.iconFont
            font.pixelSize: 11
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
