import QtQuick
import QtQuick.Layouts
import "../lib" as Lib

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
    property date now: new Date()

    // condition key (from weather.sh) -> MDI weather glyph in the Nerd Font.
    readonly property var weatherGlyphs: ({
            "clear-day": 0xF0599,           // weather-sunny
            "clear-night": 0xF0594,         // weather-night
            "partly-cloudy-day": 0xF0595,   // weather-partly-cloudy
            "partly-cloudy-night": 0xF0F31, // weather-night-partly-cloudy
            "cloudy": 0xF0590,              // weather-cloudy
            "fog": 0xF0591,                 // weather-fog
            "drizzle": 0xF0F33,             // weather-partly-rainy
            "rain": 0xF0597,                // weather-rainy
            "showers": 0xF0596,             // weather-pouring
            "sleet": 0xF067F,               // weather-snowy-rainy
            "snow": 0xF0598,                // weather-snowy
            "thunder": 0xF067E,             // weather-lightning-rainy
            "tornado": 0xF0F3A              // weather-tornado
        })
    function weatherGlyph(key) {
        var cp = root.weatherGlyphs[key];
        return String.fromCodePoint(cp ? cp : 0xF0590);
    }

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
        command: ["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/weather.sh"]
        parse: function (out) {
            try {
                var d = JSON.parse(String(out));
                return {
                    temp: d.temp ?? "--",
                    icon: d.icon ?? "cloudy",
                    desc: d.desc ?? "Unknown"
                };
            } catch (e) {
                return {
                    temp: "--",
                    icon: "cloudy",
                    desc: "Error"
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
                    text: root.weatherGlyph(weather.value ? weather.value.icon : "cloudy")
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
    }
}
