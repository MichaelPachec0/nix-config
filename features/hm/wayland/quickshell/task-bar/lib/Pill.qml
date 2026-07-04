import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Floating "pill" capsule holding a horizontal row of bar widgets. Three looks,
// driven live by the BarStyle singleton:
//   frosted     -> translucent bgPill fill (Hyprland blurs the wallpaper behind
//                  it), hairline ring, soft elevation drop; the fill carries text
//                  legibility, and glyphs get a directional depth drop.
//   ghost       -> transparent fill, hairline ring; wallpaper shows through.
//                  Legibility comes from tight per-glyph shadows (a centered
//                  black halo + a tight directional drop).
//   ghost-glass -> ghost's tight text shadows on a glass fill (frosted's blurred
//                  bgPill) -- the see-through/legible ghost text over frosted
//                  glass instead of raw wallpaper.
// Two orthogonal traits derive the branches:
//   filled      = has a bgPill fill (frosted + ghost-glass); ghost is transparent.
//   frostedText = the fill-carried text treatment (frosted only): soft elevation
//                 outer + directional depth inner. ghost + ghost-glass instead use
//                 the tight ghost shadows (halo inner + tight directional outer).
// Content is declared as children and reparented into the row:
//   Lib.Pill { theme: dock.theme; SomeWidget {} AnotherWidget {} }
Rectangle {
    id: pill

    required property QtObject theme
    property int pad: 10   // inner horizontal padding
    property int gap: 8    // spacing between content items

    readonly property string style: BarStyle.current
    readonly property bool filled: pill.style !== "ghost"
    readonly property bool frostedText: pill.style === "frosted"

    default property alias content: row.data

    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: 30
    radius: height / 2
    color: pill.filled ? pill.theme.bgPill : "transparent"
    border.width: 1
    border.color: pill.theme.border

    // Outer pass: DROP shadow. frosted = soft straight-down elevation of the glass
    // capsule; ghost / ghost-glass = a tighter down-right drop for the text. Its
    // reach is kept above the inner halo's so nesting never clips it.
    layer.enabled: true
    layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: pill.frostedText ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.85)
        shadowBlur: pill.frostedText ? 0.6 : 0.4
        blurMax: pill.frostedText ? 14 : 10
        shadowVerticalOffset: pill.frostedText ? 4 : 2
        shadowHorizontalOffset: pill.frostedText ? 0 : 2
    }

    // Inner pass: a per-glyph shadow on the content. frosted = a directional
    // down-right drop (depth/texture on the glass); ghost / ghost-glass = a
    // centered full-black halo hugging each glyph for legibility.
    Item {
        id: contentWrap
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: pill.frostedText ? Qt.rgba(0, 0, 0, 0.85) : Qt.rgba(0, 0, 0, 1.0)
            shadowBlur: 0.4
            blurMax: 6
            shadowVerticalOffset: pill.frostedText ? 2 : 0
            shadowHorizontalOffset: pill.frostedText ? 2 : 0
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
