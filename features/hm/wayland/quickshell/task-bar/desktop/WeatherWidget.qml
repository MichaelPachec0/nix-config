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

    // The SELECTED location drives the popup only.
    readonly property var loc: Locations.byId(root.weatherState.selectedId)
    // The CURRENT (geo) location drives the bar pill, always. Picking a chip
    // browses another city in the popup; it must not rewrite what the bar
    // reports, because the bar is read at a glance with no indication of which
    // city it is showing -- an 86F pill for a city 2000 miles away is a lie the
    // user has no way to notice.
    readonly property var curLoc: Locations.byId("geo")
    readonly property bool viewingCurrent: root.loc ? (root.loc.geo === true) : false

    // Popup data: whichever location is selected.
    readonly property var wx: poll.value
    // Pill data: always the current location. When the selection IS the current
    // location the two polls would fetch the same thing, so the second one is
    // switched off and this falls back to the shared poll -- weather.sh caches
    // per location, but a duplicate process every 30 min buys nothing.
    readonly property var curWx: root.viewingCurrent ? poll.value : curPoll.value
    // Not merely "the poll returned an object": weather.sh's offline fallback
    // is a well-formed record carrying temp "--", so a null check alone would
    // render that as real data with a cloud glyph beside it.
    readonly property bool hasCur: root.curWx !== null
        && String(root.curWx.temp) !== "--" && String(root.curWx.temp) !== ""

    // --- alert state: rotate the pill pulse through the CURRENT place's active
    // conditions (kind/sev/label), sourced from the shell's semantic detector.
    // A condition for a manually-selected remote city isn't where the user
    // physically is, so it must never highlight the pill -- the popup still
    // surfaces that city's own alerts when it's open.
    readonly property var conds: (root.curWx && root.curWx.conditions) ? WeatherCond.sortBySeverity(root.curWx.conditions) : []
    property int condIdx: 0
    onCondsChanged: root.condIdx = 0
    readonly property var curCond: root.conds.length > 0 ? root.conds[root.condIdx % root.conds.length] : null
    // Legacy string kept for the Pill binding; empty -> no pulse.
    readonly property string alert: root.curCond ? root.curCond.kind : ""
    readonly property color alertColor: root.curCond ? WeatherCond.color(root.theme, root.curCond.kind, root.curCond.sev) : "transparent"

    // Pulse rhythm. Advancing on a free-running timer made two conditions read
    // as one stutter: the timer and the pill's own ~5s flash cycle drifted, so
    // the colour often changed mid-flash. The pill now drives this instead --
    // it emits `pulsed` when a flash finishes, and the gap BEFORE the next one
    // is short between conditions and long after the last, which groups the
    // set audibly: flash, beat, flash, ..... flash, beat, flash, .....
    property int pulseShortGapMs: 700
    property int pulseLongGapMs: 4300
    property int pulseGapMs: root.pulseLongGapMs
    function advancePulse() {
        var n = root.conds.length;
        if (n <= 1) {
            root.pulseGapMs = root.pulseLongGapMs;
            return;
        }
        // Gap length describes the condition that JUST flashed, so decide it
        // before advancing.
        var isLast = (root.condIdx % n) === (n - 1);
        root.pulseGapMs = isLast ? root.pulseLongGapMs : root.pulseShortGapMs;
        root.condIdx = isLast ? 0 : (root.condIdx + 1);
    }

    // Always visible, even with no reading: a pill that vanishes is
    // indistinguishable from a pill reporting good weather, and the bar's
    // layout shifting on every failed fetch is its own annoyance. "--" says
    // "no data" out loud.
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    // Refetch immediately when the location changes (after the command binding
    // updates this tick).
    onLocChanged: Qt.callLater(poll.poll)

    // Lib.WakeService, threaded down from shell.qml via Taskbar.
    property var wakeSvc: null

    // A suspend is the one event that reliably invalidates WHERE we are, and
    // the poll interval is 30 minutes -- long enough to sit in a new city
    // showing the old one's weather until the next tick happens to land.
    // weather.sh independently expires its own caches against the same stamp,
    // so this only decides WHEN the refetch happens, never what it returns.
    //
    // resetDedup() because CommandPoll suppresses a result byte-identical to
    // the previous one: waking where you fell asleep would otherwise skip
    // updated(), and the fetch timestamp the popup shows would never advance.
    Connections {
        target: root.wakeSvc
        function onWoke() {
            poll.resetDedup();
            poll.poll();
            if (curPoll.running) {
                curPoll.resetDedup();
                curPoll.poll();
            }
        }
    }

    Lib.CommandPoll {
        id: poll
        interval: 1800000 // 30 min; weather.sh caches the same window
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/weather.sh"].concat(Locations.argsArrayFor(root.loc))
        parse: function (out) {
            return root._parseWx(out);
        }
    }

    // Current-location poll, live only while the popup is browsing some OTHER
    // city. See curWx above for why it is not simply always on.
    Lib.CommandPoll {
        id: curPoll
        interval: 1800000
        running: !root.viewingCurrent
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/weather.sh"].concat(Locations.argsArrayFor(root.curLoc))
        parse: function (out) {
            return root._parseWx(out);
        }
    }

    function _parseWx(out) {
            try {
                var d = JSON.parse(String(out));
                return {
                    asOf: d.asOf ?? 0,
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

    // The alert pulse itself is rendered by the enclosing Lib.Pill (bound to
    // root.alert / root.alertColor in the taskbar) so the colour fills the whole
    // capsule uniformly instead of a rectangle behind just this content.

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5

        // Hidden with no reading rather than defaulted to a cloud: a condition
        // glyph is a claim about the sky, and rendering one next to "--" would
        // assert something the widget does not know.
        Lib.BarText {
            visible: root.hasCur
            Layout.alignment: Qt.AlignVCenter
            text: WeatherIcons.glyph(root.hasCur ? root.curWx.icon : "cloudy")
            color: root.theme.weatherIcon
            font.family: root.theme.iconFont
            font.pixelSize: 13
        }
        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            text: root.hasCur ? (root.curWx.temp + String.fromCodePoint(0x00B0)) : "--"
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
    Lib.HoverBridge {
        popup: popup
        widgetHovered: widgetHover.hovered
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
