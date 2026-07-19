import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons
import "../lib/locations.js" as Locations

// Hub Calendar/Weather card (Phase 2d, step 7). Left: a large date block
// (weekday / day-number / month-year). Right: current weather (glyph + temp +
// description). Below: a month grid with today highlighted. Weather comes from
// lib/weather.sh (OpenWeatherMap when an API key is wired, else wttr.in), polled
// every 30 min while the hub is open. Adapted from surface-dots; Gruvbox tokens
// and Nerd Font (MDI) weather glyphs in place of surface-dots' emoji icons.
Rectangle {
    id: root

    required property QtObject theme
    property bool active: true
    property var weatherState: null
    property date now: new Date()

    readonly property var loc: root.weatherState ? Locations.byId(root.weatherState.selectedId) : null
    onLocChanged: Qt.callLater(weather.poll)

    implicitHeight: col.implicitHeight + 24
    radius: root.theme.radiusOuter
    color: root.theme.bgCard
    border.width: 1
    border.color: root.theme.border

    // Refresh the displayed date once a minute while the hub is open.
    Timer {
        interval: 60000
        repeat: true
        running: root.active && root.visible
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Lib.CommandPoll {
        id: weather
        running: root.active && root.visible
        interval: 1800000 // 30 min; weather.sh caches for the same window
        command: ["bash", "-c", "$HOME/.config/quickshell/task-bar/lib/weather.sh " + Locations.argsFor(root.loc)]
        parse: function (out) {
            try {
                var d = JSON.parse(String(out));
                return {
                    temp: d.temp ?? "--",
                    icon: d.icon ?? "cloudy",
                    desc: d.desc ?? "Unknown",
                    place: d.place ?? ""
                };
            } catch (e) {
                return {
                    temp: "--",
                    icon: "cloudy",
                    desc: "Error",
                    place: ""
                };
            }
        }
    }

    ColumnLayout {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 6

        // Top row: large date block (left) + weather (right).
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Date block.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: Qt.formatDate(root.now, "dddd").toUpperCase()
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    color: root.theme.accent
                    opacity: 0.9
                }
                Text {
                    text: Qt.formatDate(root.now, "d")
                    font.family: root.theme.textFont
                    font.pixelSize: 60
                    font.weight: Font.ExtraBold
                    color: root.theme.textPrimary
                    lineHeight: 0.85
                    lineHeightMode: Text.ProportionalHeight
                }
                Text {
                    text: Qt.formatDate(root.now, "MMMM yyyy").toUpperCase()
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.0
                    color: root.theme.textSecondary
                    opacity: 0.7
                }
            }

            // Weather.
            ColumnLayout {
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: WeatherIcons.glyph(weather.value ? weather.value.icon : "cloudy")
                    font.family: root.theme.iconFont
                    font.pixelSize: 34
                    color: root.theme.weatherIcon
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: (weather.value ? weather.value.temp : "--") + String.fromCodePoint(0x00B0)
                    font.family: root.theme.textFont
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: root.theme.textPrimary
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: 120
                    text: weather.value ? weather.value.desc : "Loading"
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                    color: root.theme.textSecondary
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: 120
                    text: (weather.value && weather.value.place) ? weather.value.place : ""
                    visible: text !== ""
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    font.family: root.theme.textFont
                    font.pixelSize: 9
                    color: root.theme.textSecondary
                    opacity: 0.75
                }
            }
        }

        // Month calendar grid, right-aligned under the weather.
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.preferredHeight: calGrid.implicitHeight

            CalendarGrid {
                id: calGrid
                anchors.right: parent.right
                theme: root.theme
                when: root.now
            }
        }

        // Location chips (shared selection with the bar weather widget).
        Lib.LocationChips {
            Layout.topMargin: 2
            Layout.alignment: Qt.AlignLeft
            visible: root.weatherState !== null
            theme: root.theme
            weatherState: root.weatherState
        }
    }
}
