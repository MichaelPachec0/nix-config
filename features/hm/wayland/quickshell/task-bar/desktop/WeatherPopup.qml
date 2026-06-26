import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib/weathericons.js" as WeatherIcons

// Current-conditions popup shown on hover over the bar weather widget. Read-only,
// so it's a plain non-grab tooltip anchored under the bar. Shows the big glyph +
// temperature, description, location, and which provider answered.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    property var wx: null // {temp, icon, desc, source}

    implicitWidth: 220
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

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 6

            // Header: glyph + big temperature.
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
                    text: (pop.wx ? pop.wx.temp : "--") + String.fromCodePoint(0x00B0)
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 26
                    font.weight: Font.Bold
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // Description.
            Text {
                Layout.fillWidth: true
                text: pop.wx ? pop.wx.desc : ""
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            // Location.
            Text {
                text: "Los Angeles"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 11
            }

            // Provider provenance.
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
