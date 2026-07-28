// features/hm/wayland/quickshell/task-bar/lock/LockBackdrop.qml
// Swappable lock backdrop. MVP: a wallpaper image, GPU-blurred. v2 swaps `source`
// for a ScreencopyView frozen frame; the blur pipeline is unchanged.
import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property string source: ""

    Image {
        id: img
        anchors.fill: parent
        source: root.source ? ("file://" + root.source) : ""
        fillMode: Image.PreserveAspectCrop
        cache: false
        asynchronous: true
        visible: false // shown via the blur effect
    }

    GaussianBlur {
        anchors.fill: parent
        source: img
        radius: 64
        samples: 33
        // Dim overlay so the input field stays legible over bright wallpapers.
    }
    Rectangle {
        anchors.fill: parent
        color: "#1d2021"
        opacity: 0.35
    }
}
