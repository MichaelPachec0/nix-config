import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons
import "../lib/locations.js" as Locations
import "../lib/weathercond.js" as WeatherCond

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

    // --- alert state: rotate the pill pulse through the current place's active
    // conditions (kind/sev/label), sourced from the shell's semantic detector.
    // Only the CURRENT location pulses the bar pill. A condition for a
    // manually-selected remote city (LA/SF/NYC/Durango) isn't where the user
    // physically is, so it must never highlight the pill -- the popup still
    // surfaces that city's own alerts when it's open.
    readonly property bool isCurrentPlace: root.loc ? (root.loc.geo === true) : false
    readonly property var conds: (root.isCurrentPlace && root.wx && root.wx.conditions) ? WeatherCond.sortBySeverity(root.wx.conditions) : []
    property int condIdx: 0
    onCondsChanged: root.condIdx = 0
    readonly property var curCond: root.conds.length > 0 ? root.conds[root.condIdx % root.conds.length] : null
    // Legacy string kept for the Pill binding; empty -> no pulse.
    readonly property string alert: root.curCond ? root.curCond.kind : ""
    readonly property color alertColor: root.curCond ? WeatherCond.color(root.theme, root.curCond.kind, root.curCond.sev) : "transparent"
    Timer {
        interval: 2500
        repeat: true
        running: root.conds.length > 1
        onTriggered: root.condIdx = (root.condIdx + 1) % root.conds.length
    }

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
                    alerts: d.alerts ?? [],
                    conditions: d.conditions ?? [],
                    nowcast: d.nowcast ?? ({ rainSoon: false, etaMin: null, source: "none", text: "" })
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
