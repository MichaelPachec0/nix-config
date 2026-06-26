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

    // --- alert state: pulse the widget when today's weather is notable --------
    // Heat is read off the current temperature (>=85 orange, >=90 red); rain off
    // today's forecast (or a current rainy condition) -> blue. Heat wins.
    function isRainy(k) {
        return k === "rain" || k === "showers" || k === "drizzle" || k === "thunder";
    }
    readonly property int curTemp: (root.wx && root.wx.temp) ? (parseInt(root.wx.temp) || 0) : 0
    readonly property var today: (root.wx && root.wx.forecast && root.wx.forecast.length > 0) ? root.wx.forecast[0] : null
    readonly property bool rainToday: (root.today && root.isRainy(root.today.icon)) || (root.wx ? root.isRainy(root.wx.icon) : false)
    readonly property string alert: {
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

    // Pulsing alert glow behind the content (every 5s while an alert is active).
    Rectangle {
        id: flashBg
        anchors.fill: parent
        anchors.margins: -3
        radius: 6
        z: -1
        color: root.alertColor
        opacity: 0
    }
    SequentialAnimation {
        id: flashAnim
        NumberAnimation {
            target: flashBg
            property: "opacity"
            from: 0
            to: 0.55
            duration: 220
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: flashBg
            property: "opacity"
            to: 0
            duration: 480
            easing.type: Easing.InQuad
        }
    }
    Timer {
        interval: 5000
        running: root.alert !== "" && root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: flashAnim.start()
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
