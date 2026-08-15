import QtQuick
import QtQuick.Layouts
import "modefmt.js" as ModeFmt

// The submap icon glyph plus its label. Shared by the bar pill
// (desktop/ModePill.qml) and the fullscreen overlay (desktop/ModeOverlay.qml)
// so the glyph, fonts, sizes and accent colour cannot drift between the two.
//
// Owns no layout policy beyond its own spacing: each consumer drops it into its
// own Lib.Pill as a single content item, which is why the consumers no longer
// set Pill.gap.
RowLayout {
    id: badge

    required property QtObject theme
    required property var svc

    spacing: 6

    readonly property string glyph: badge.svc ? ModeFmt.glyphFor(badge.svc.iconCp()) : ""

    BarText {
        Layout.alignment: Qt.AlignVCenter
        visible: badge.glyph !== ""
        text: badge.glyph
        font.family: badge.theme.faFont
        font.pixelSize: 12
        color: badge.theme.accent
    }
    BarText {
        Layout.alignment: Qt.AlignVCenter
        text: badge.svc ? badge.svc.label() : ""
        font.family: badge.theme.iconFont
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: badge.theme.accent
    }
}
