// features/hm/wayland/quickshell/task-bar/lock/LockText.qml
// Lock text with a raised/shadowed edge so it stays legible over any blurred
// wallpaper (light or dark). A Text subtype: callers set text/color/font and inherit
// the shadow. (Style tuned later; start with a raised dark shadow.)
import QtQuick

Text {
    color: "#ebdbb2"
    style: Text.Raised
    styleColor: Qt.rgba(0, 0, 0, 0.6)
}
