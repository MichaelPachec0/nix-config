import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons
import "../lib/weathercond.js" as WeatherCond
import "../lib/notiftime.js" as NotifTime

// Current-conditions + forecast popup shown on hover over the bar weather
// widget. Read-only, so it's a plain non-grab tooltip anchored under the bar.
// Header (glyph + temp + description), current detail rows (feels-like, humidity,
// wind -- each hidden when the active provider doesn't supply it), then a 3-day
// forecast strip, with location and provider provenance at the foot.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    required property var weatherState
    property var wx: null // {temp, icon, desc, source, feels, humidity, precip, wind, windDir, place, forecast[], hourly[]}

    // Tracks hover over the popup card so the widget can keep it open (chips
    // inside need to stay clickable when the cursor leaves the bar widget).
    property bool contentHovered: cardHover.hovered

    readonly property string deg: String.fromCodePoint(0x00B0)
    readonly property string feels: (pop.wx && pop.wx.feels) ? pop.wx.feels : ""
    readonly property string humidity: (pop.wx && pop.wx.humidity) ? pop.wx.humidity : ""
    readonly property string precip: (pop.wx && pop.wx.precip) ? pop.wx.precip : ""
    readonly property string wind: (pop.wx && pop.wx.wind) ? pop.wx.wind : ""
    readonly property string windDir: (pop.wx && pop.wx.windDir) ? pop.wx.windDir : ""
    readonly property string place: (pop.wx && pop.wx.place) ? pop.wx.place : ""
    readonly property var forecast: (pop.wx && pop.wx.forecast) ? pop.wx.forecast : []
    readonly property var hourly: (pop.wx && pop.wx.hourly) ? pop.wx.hourly : []
    readonly property string uv: (pop.wx && pop.wx.uv) ? pop.wx.uv : ""
    readonly property string windGust: (pop.wx && pop.wx.windGust) ? pop.wx.windGust : ""
    readonly property string precipType: (pop.wx && pop.wx.precipType) ? pop.wx.precipType : ""
    readonly property string sunrise: (pop.wx && pop.wx.sunrise) ? pop.wx.sunrise : ""
    readonly property string sunset: (pop.wx && pop.wx.sunset) ? pop.wx.sunset : ""
    readonly property var alerts: (pop.wx && pop.wx.alerts) ? pop.wx.alerts : []

    // UV index band word / "7  High" label / severity colour (green/yellow/red,
    // reusing the Sys severity palette). Empty in -> empty out (row self-hides).
    function uvBand(v) {
        var n = parseInt(v);
        if (v === "" || isNaN(n))
            return "";
        return n <= 2 ? "Low" : (n <= 5 ? "Moderate" : (n <= 7 ? "High" : (n <= 10 ? "Very high" : "Extreme")));
    }
    function uvLabel(v) {
        var b = pop.uvBand(v);
        return b === "" ? "" : (parseInt(v) + "  " + b);
    }
    function uvColor(v) {
        var n = parseInt(v);
        if (isNaN(n))
            return pop.theme.textPrimary;
        // Green -> yellow -> purple; High+ (>=6, the flash threshold) is purple,
        // giving UV its own identity distinct from the red/yellow NWS alerts.
        return n <= 2 ? pop.theme.accentGreen : (n <= 5 ? pop.theme.accentYellow : pop.theme.accentPurple);
    }
    // Precip row label reflects the type when the provider gives one.
    function precipLabel(t) {
        return t === "snow" ? "Chance of snow" : (t === "sleet" ? "Chance of sleet" : "Chance of rain");
    }

    // Active conditions, severest first: driven straight from the shell's
    // semantic conditions[] (which already folds in NWS alerts as kind "nws").
    // Rendered one card per entry, all in view -- see the Repeater below.
    readonly property var alertsAll: {
        var src = (pop.wx && pop.wx.conditions) ? pop.wx.conditions : [];
        return WeatherCond.sortBySeverity(src).map(function (c) {
            return {
                kind: c.kind,
                title: c.label,
                sev: c.sev,
                // Only NWS alerts carry one; every other kind is derived from
                // the current snapshot and ends whenever the next poll says so.
                expires: c.expires ? (c.expires * 1000) : 0
            };
        });
    }

    // When this reading was FETCHED, from weather.sh's asOf. Not the time the
    // popup opened: results are cached for 30 min and a stale cache is served
    // when every provider fails, so the two can be hours apart.
    readonly property double asOfMs: (pop.wx && pop.wx.asOf) ? (pop.wx.asOf * 1000) : 0

    // Live clock for the relative times. Only ticks while the popup is open --
    // a 1s timer behind a closed tooltip is pure waste, and the values are
    // recomputed on show anyway.
    property double nowMs: 0
    Timer {
        interval: 1000
        repeat: true
        running: pop.visible
        triggeredOnStart: true
        onTriggered: pop.nowMs = Date.now()
    }

    implicitWidth: 250
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
    }
    function hide() {
        pop.visible = false;
    }

    // One "label ........ value" line; hidden when value is empty. valueColor
    // lets a row tint its value (e.g. UV severity); defaults to the primary text.
    component DetailRow: RowLayout {
        property string label: ""
        property string value: ""
        property color valueColor: pop.theme.textPrimary
        Layout.fillWidth: true
        visible: value !== ""
        Text {
            text: parent.label
            color: pop.theme.textSecondary
            font.family: pop.theme.textFont
            font.pixelSize: 11
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: parent.value
            color: parent.valueColor
            font.family: pop.theme.textFont
            font.pixelSize: 11
        }
    }

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        HoverHandler {
            id: cardHover
        }

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 7

            // Every active condition gets its OWN card, all in view at once.
            // They used to share one banner that rotated through them on a
            // timer, which meant a second advisory was invisible for most of
            // the time the popup was open -- and the popup is the surface you
            // open precisely to see everything at once. The bar pill still
            // cycles, because a pill has room for one.
            Repeater {
                model: pop.alertsAll
                Rectangle {
                    id: alertCard
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: alertBody.implicitHeight + 10
                    radius: 6

                    // Colour keyed off the condition's kind/sev, shared with the
                    // rest of the weather UI (WeatherCond.color).
                    readonly property color sev: WeatherCond.color(pop.theme, alertCard.modelData.kind, alertCard.modelData.sev)

                    // Static tint. The cards no longer flash: several of them
                    // pulsing at once is noise, and with all of them on screen
                    // there is nothing left to attract attention TO. The bar
                    // pill carries the flashing.
                    color: Qt.rgba(alertCard.sev.r, alertCard.sev.g, alertCard.sev.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(alertCard.sev.r, alertCard.sev.g, alertCard.sev.b, 0.45)

                    Column {
                        id: alertBody
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 1

                        Text {
                            width: parent.width
                            text: alertCard.modelData.title
                            color: pop.theme.textPrimary
                            font.family: pop.theme.textFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }

                        // When this reading was taken, and how long ago. Shared
                        // with the notification stamps (NotifTime.fmtStamp) so
                        // "14:32 (2m ago)" means the same thing everywhere.
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: NotifTime.fmtStamp(pop.nowMs, pop.asOfMs, true)
                            color: pop.theme.textSecondary
                            font.family: pop.theme.textFont
                            font.pixelSize: 9
                        }

                        // Deadline, when the condition has one. Only NWS alerts
                        // do -- "Heat advisory until 6 PM" is knowable, "Gusts
                        // 40 mph" is not -- so this row self-hides rather than
                        // inventing an end time for the derived kinds.
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: {
                                var u = WeatherCond.fmtUntil(pop.nowMs, alertCard.modelData.expires, true);
                                return u === "" ? "" : ("until " + u);
                            }
                            color: pop.theme.textSecondary
                            font.family: pop.theme.textFont
                            font.pixelSize: 9
                        }
                    }
                }
            }

            // Header: glyph + big temperature + description.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: WeatherIcons.glyph(pop.wx ? pop.wx.icon : "cloudy")
                    color: pop.theme.weatherIcon
                    font.family: pop.theme.iconFont
                    font.pixelSize: 30
                }
                Text {
                    text: (pop.wx ? pop.wx.temp : "--") + pop.deg
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 26
                    font.weight: Font.Bold
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    Layout.maximumWidth: 110
                    horizontalAlignment: Text.AlignRight
                    text: pop.wx ? pop.wx.desc : ""
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // Current detail rows (each self-hides when unavailable).
            DetailRow {
                label: "Feels like"
                value: pop.feels !== "" ? pop.feels + pop.deg : ""
            }
            DetailRow {
                label: "Humidity"
                value: pop.humidity !== "" ? pop.humidity + "%" : ""
            }
            DetailRow {
                label: pop.precipLabel(pop.precipType)
                value: pop.precip !== "" ? pop.precip + "%" : ""
            }
            DetailRow {
                label: "Wind"
                value: pop.wind !== "" ? (pop.wind + " mph" + (pop.windDir !== "" ? " " + pop.windDir : "") + (pop.windGust !== "" ? ", gusts " + pop.windGust : "")) : ""
            }
            DetailRow {
                label: "UV index"
                value: pop.uvLabel(pop.uv)
                valueColor: pop.uvColor(pop.uv)
            }
            DetailRow {
                label: "Sunrise"
                value: pop.sunrise
            }
            DetailRow {
                label: "Sunset"
                value: pop.sunset
            }

            // Divider before the hourly strip.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 1
                implicitHeight: 1
                color: pop.theme.border
                visible: pop.hourly.length > 0
            }

            // Next-12-hours strip: horizontally scrollable when it overflows the
            // popup width. Provider-dependent (currently Pirate Weather only); the
            // whole block self-hides when the active provider supplies no hourly.
            // Each cell: hour label, icon (night variants kept), temp, and precip
            // chance when non-zero.
            Flickable {
                Layout.fillWidth: true
                Layout.topMargin: 1
                implicitHeight: hourRow.implicitHeight
                contentWidth: hourRow.implicitWidth
                contentHeight: hourRow.implicitHeight
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                visible: pop.hourly.length > 0

                Row {
                    id: hourRow
                    spacing: 8
                    Repeater {
                        model: pop.hourly
                        Column {
                            required property var modelData
                            width: 34
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.h
                                color: pop.theme.textSecondary
                                font.family: pop.theme.textFont
                                font.pixelSize: 10
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: WeatherIcons.glyph(modelData.icon)
                                color: pop.theme.weatherIcon
                                font.family: pop.theme.iconFont
                                font.pixelSize: 15
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.temp + pop.deg
                                color: pop.theme.textPrimary
                                font.family: pop.theme.textFont
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.uv !== "" ? ("UV " + modelData.uv) : ""
                                visible: modelData.uv !== ""
                                color: pop.uvColor(modelData.uv)
                                font.family: pop.theme.textFont
                                font.pixelSize: 9
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.precip + "%"
                                visible: modelData.precip !== "" && modelData.precip !== "0"
                                color: pop.theme.textSecondary
                                font.family: pop.theme.textFont
                                font.pixelSize: 9
                                opacity: 0.85
                            }
                        }
                    }
                }
            }

            // Divider before the forecast.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 1
                implicitHeight: 1
                color: pop.theme.border
                visible: pop.forecast.length > 0
            }

            // Multi-day forecast (vertical list; up to 7 days, fewer if the
            // active provider supplies fewer -- wttr.in caps at 3, OWM at 5).
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 1
                spacing: 5
                visible: pop.forecast.length > 0

                Repeater {
                    model: pop.forecast
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.preferredWidth: 28
                            text: modelData.day
                            color: pop.theme.textPrimary
                            font.family: pop.theme.textFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: WeatherIcons.glyph(modelData.icon)
                            color: pop.theme.weatherIcon
                            font.family: pop.theme.iconFont
                            font.pixelSize: 15
                        }
                        Text {
                            Layout.fillWidth: true
                            text: WeatherIcons.descFromKey(modelData.icon)
                            color: pop.theme.textSecondary
                            font.family: pop.theme.textFont
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.hi + pop.deg
                            color: pop.theme.textPrimary
                            font.family: pop.theme.textFont
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.preferredWidth: 26
                            horizontalAlignment: Text.AlignRight
                            text: modelData.lo + pop.deg
                            color: pop.theme.textSecondary
                            font.family: pop.theme.textFont
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Location chips (selectable; shared with the hub card).
            Lib.LocationChips {
                Layout.topMargin: 2
                theme: pop.theme
                weatherState: pop.weatherState
            }

            // Foot: resolved place (full city, state, country) + provider
            // provenance. The place fills and elides so a long name can't push the
            // provider label off the row; the provider keeps its natural width.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: pop.place
                    elide: Text.ElideRight
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                }
                Text {
                    visible: text !== ""
                    text: pop.wx ? ("via " + WeatherIcons.sourceLabel(pop.wx.source)) : ""
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                    opacity: 0.7
                }
            }
        }
    }
}
