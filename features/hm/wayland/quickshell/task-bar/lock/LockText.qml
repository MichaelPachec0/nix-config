// features/hm/wayland/quickshell/task-bar/lock/LockText.qml
// Lock text with a light outline PLUS a strong soft drop shadow, so it stays legible
// over any blurred wallpaper (light or dark). A Text subtype: callers set text/color/
// font and inherit the edge treatment. (Shadow tuned visually.)
import QtQuick
import Qt5Compat.GraphicalEffects

Text {
    color: "#ebdbb2"
    style: Text.Outline
    styleColor: Qt.rgba(0, 0, 0, 0.4)

    layer.enabled: true
    layer.effect: DropShadow {
        horizontalOffset: 0
        verticalOffset: 3
        radius: 12
        samples: 25
        color: Qt.rgba(0, 0, 0, 1.0)
    }
}
