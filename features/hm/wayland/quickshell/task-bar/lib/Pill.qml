import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Floating "pill" capsule holding a horizontal row of bar widgets. Two looks,
// driven live by the BarStyle singleton:
//   frosted -> translucent bgPill fill, hairline ring, soft elevation shadow
//              (Hyprland blurs the wallpaper behind the fill).
//   ghost   -> transparent fill, hairline ring; the wallpaper shows through.
// Ghost legibility comes from the crisp per-glyph outline on Lib.BarText
// (Text.Outline). On top of that, ghost adds two shadow passes:
//   inner -> a tight ~2px soft black halo around the content, which fattens the
//            crisp 1px outline and blends it into the drop.
//   outer -> a directional drop for depth.
// Frosted uses only the outer pass (soft elevation); its fill carries legibility.
// Content is declared as children and reparented into the row:
//   Lib.Pill { theme: dock.theme; SomeWidget {} AnotherWidget {} }
Rectangle {
    id: pill

    required property QtObject theme
    property int pad: 10   // inner horizontal padding
    property int gap: 8    // spacing between content items

    readonly property bool frosted: BarStyle.current !== "ghost"

    default property alias content: row.data

    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: 30
    radius: height / 2
    color: pill.frosted ? pill.theme.bgPill : "transparent"
    border.width: 1
    border.color: pill.theme.border

    // Outer pass: directional DROP shadow (depth). Frosted = soft straight-down
    // elevation; ghost = a tighter down-right drop. Its reach (blurMax*blur +
    // offset) is kept well above the inner halo's so nesting never clips it.
    layer.enabled: true
    layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: pill.frosted ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 1.0)
        shadowBlur: pill.frosted ? 0.7 : 0.6
        blurMax: pill.frosted ? 32 : 24
        shadowVerticalOffset: pill.frosted ? 3 : 3
        shadowHorizontalOffset: pill.frosted ? 0 : 2
    }

    // Inner pass (ghost only): a tight ~2px soft black halo around the content --
    // full black, offset 0, small blur -- so the crisp Text.Outline reads as a
    // softer ~2px outline that blends into the drop shadow.
    Item {
        id: contentWrap
        anchors.fill: parent
        layer.enabled: !pill.frosted
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 1.0)
            shadowBlur: 0.8
            blurMax: 8
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
        }

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: pill.pad
            spacing: pill.gap
        }
    }
}
