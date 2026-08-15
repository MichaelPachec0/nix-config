// features/hm/wayland/quickshell/task-bar/lock/LockText.qml
// Lock text with a TUNABLE outline + drop shadow so it reads over any blurred
// wallpaper (light or dark). A Text subtype: callers set text/color/font, and may
// SOFTEN the edge treatment (e.g. small text on a solid-colour chip, where the
// strong default overpowers the glyphs) via shadowRadius/shadowOffset/
// shadowOpacity/outlineOpacity. Defaults are strong -- tuned for the large
// clock/date floating directly over the wallpaper.
import QtQuick
import Qt5Compat.GraphicalEffects

Text {
    id: lt
    property real shadowRadius: 12
    property real shadowOffset: 3
    property real shadowOpacity: 1.0
    property real outlineOpacity: 0.4
    property color shadowColor: "#000000"

    color: "#ebdbb2"
    style: Text.Outline
    styleColor: Qt.rgba(0, 0, 0, lt.outlineOpacity)

    layer.enabled: true
    layer.effect: DropShadow {
        horizontalOffset: 0
        verticalOffset: lt.shadowOffset
        radius: lt.shadowRadius
        samples: Math.round(lt.shadowRadius * 2 + 1)
        color: Qt.rgba(lt.shadowColor.r, lt.shadowColor.g, lt.shadowColor.b, lt.shadowOpacity)
    }
}
