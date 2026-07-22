import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons

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

    // Unified flashing-alert list: the provider's NWS alerts plus a synthetic
    // "High UV" alert when the index is High (>=6). The banner below flashes for
    // attention and, when there's more than one, rotates through them one after
    // the other (alertIdx, advanced by a timer).
    readonly property var alertsAll: {
        var out = [];
        var a = pop.alerts || [];
        for (var i = 0; i < a.length; i++)
            out.push({
                kind: "nws",
                title: a[i].title || "Weather alert",
                severity: a[i].severity || "",
                expires: a[i].expires || 0
            });
        var n = parseInt(pop.uv);
        if (!isNaN(n) && n >= 6)
            out.push({
                kind: "uv",
                title: "UV index " + pop.uvBand(pop.uv).toLowerCase() + " (" + n + ")",
                severity: n >= 8 ? "warning" : "advisory",
                expires: 0
            });
        return out;
    }
    property int alertIdx: 0
    onAlertsAllChanged: pop.alertIdx = 0 // restart the rotation when the set changes

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

            // Alert banner: the provider's NWS alerts + a synthetic High-UV alert
            // (see alertsAll), shown one at a time. It flashes for attention and,
            // when there's more than one, rotates through them one after the other.
            // Read-only -- the popup is a non-grab tooltip, so there's no tap-to-open.
            Rectangle {
                id: alertBanner
                readonly property var cur: pop.alertsAll.length > 0 ? pop.alertsAll[pop.alertIdx % pop.alertsAll.length] : null
                visible: cur !== null
                Layout.fillWidth: true
                implicitHeight: alertBody.implicitHeight + 10
                radius: 6

                // UV alerts get their own purple identity; NWS alerts are red for a
                // warning/watch/emergency, yellow for an advisory.
                readonly property color sev: {
                    if (!cur)
                        return pop.theme.accentYellow;
                    if (cur.kind === "uv")
                        return pop.theme.accentPurple;
                    var s = (cur.severity || "").toLowerCase();
                    return (s.indexOf("warn") >= 0 || s.indexOf("emerg") >= 0 || s.indexOf("watch") >= 0) ? pop.theme.accentRed : pop.theme.accentYellow;
                }

                // Flash: pulse the tint + border while an alert is up.
                property real flash: 0
                SequentialAnimation on flash {
                    running: alertBanner.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0
                        to: 1
                        duration: 650
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: 1
                        to: 0
                        duration: 650
                        easing.type: Easing.InOutSine
                    }
                }
                color: Qt.rgba(alertBanner.sev.r, alertBanner.sev.g, alertBanner.sev.b, 0.12 + 0.24 * alertBanner.flash)
                border.width: 1
                border.color: Qt.rgba(alertBanner.sev.r, alertBanner.sev.g, alertBanner.sev.b, 0.40 + 0.5 * alertBanner.flash)

                // Rotate one after the other (only when there's more than one).
                Timer {
                    interval: 3000
                    repeat: true
                    running: pop.visible && pop.alertsAll.length > 1
                    onTriggered: pop.alertIdx = (pop.alertIdx + 1) % pop.alertsAll.length
                }

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
                        text: (pop.alertsAll.length > 1 ? ("(" + (pop.alertIdx % pop.alertsAll.length + 1) + "/" + pop.alertsAll.length + ")  ") : "") + (alertBanner.cur ? alertBanner.cur.title : "")
                        color: pop.theme.textPrimary
                        font.family: pop.theme.textFont
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: (alertBanner.cur && alertBanner.cur.expires) ? ("until " + Qt.formatDateTime(new Date(alertBanner.cur.expires * 1000), "ddd h:mm AP")) : ""
                        color: pop.theme.textSecondary
                        font.family: pop.theme.textFont
                        font.pixelSize: 9
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
