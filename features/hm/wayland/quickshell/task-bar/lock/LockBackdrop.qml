// features/hm/wayland/quickshell/task-bar/lock/LockBackdrop.qml
// Swappable lock backdrop. The wallpaper Image is the sharp base layer; a
// constant-radius GaussianBlur of it is cross-faded on top via `blurAmount`,
// together with the dim overlay. Animating the blur's OPACITY (not its radius)
// keeps the kernel constant -- animating `radius` would regenerate the blur
// kernel every frame. blurAmount 0 = sharp/undimmed, 1 = the original MVP end
// state (radius 9, dim 0.35).
import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property string source: ""
    property real blurAmount: 1.0
    property int animDuration: 350

    Behavior on blurAmount {
        NumberAnimation {
            duration: root.animDuration
            easing.type: Easing.OutCubic
        }
    }

    // Sharp base. Visible (unlike the MVP, where the blur was the only layer)
    // so blurAmount can fade between sharp and blurred.
    Image {
        id: img
        anchors.fill: parent
        source: root.source ? ("file://" + root.source) : ""
        fillMode: Image.PreserveAspectCrop
        cache: false
        asynchronous: true
    }

    // Blurred copy, cross-faded over the sharp base. Qt5Compat's GaussianBlur
    // wraps its source in a SourceProxy, which passes a plain Image straight
    // through as a texture provider without hiding it -- so `img` stays on
    // screen as the sharp base while the blur samples the same texture.
    GaussianBlur {
        anchors.fill: parent
        source: img
        radius: 9
        samples: 11
        opacity: root.blurAmount
    }

    // Dim overlay so the input field stays legible over bright wallpapers.
    Rectangle {
        anchors.fill: parent
        color: "#1d2021"
        opacity: root.blurAmount * 0.35
    }
}
