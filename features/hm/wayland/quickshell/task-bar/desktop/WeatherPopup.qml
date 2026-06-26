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
    property var wx: null // {temp, icon, desc, source, feels, humidity, wind, windDir, place, forecast[]}

    // Tracks hover over the popup card so the widget can keep it open (chips
    // inside need to stay clickable when the cursor leaves the bar widget).
    property bool contentHovered: cardHover.hovered

    readonly property string deg: String.fromCodePoint(0x00B0)
    readonly property string feels: (pop.wx && pop.wx.feels) ? pop.wx.feels : ""
    readonly property string humidity: (pop.wx && pop.wx.humidity) ? pop.wx.humidity : ""
    readonly property string wind: (pop.wx && pop.wx.wind) ? pop.wx.wind : ""
    readonly property string windDir: (pop.wx && pop.wx.windDir) ? pop.wx.windDir : ""
    readonly property string place: (pop.wx && pop.wx.place) ? pop.wx.place : ""
    readonly property var forecast: (pop.wx && pop.wx.forecast) ? pop.wx.forecast : []

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

    // One "label ........ value" line; hidden when value is empty.
    component DetailRow: RowLayout {
        property string label: ""
        property string value: ""
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
            color: pop.theme.textPrimary
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
                label: "Wind"
                value: pop.wind !== "" ? (pop.wind + " mph" + (pop.windDir !== "" ? " " + pop.windDir : "")) : ""
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

            // Foot: resolved place + provider provenance.
            RowLayout {
                Layout.fillWidth: true
                Text {
                    visible: text !== ""
                    text: pop.place
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                }
                Item {
                    Layout.fillWidth: true
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
