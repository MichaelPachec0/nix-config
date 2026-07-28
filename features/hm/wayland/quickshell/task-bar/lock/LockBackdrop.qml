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

    // This output's frozen desktop capture (ScreencopyView from Lock.qml's
    // pool), or null. Reparented in below so it renders inside THIS surface's
    // scene graph -- a GaussianBlur cannot source an item from another window.
    property var capture: null

    // Use the capture only once it actually holds a frame; otherwise the
    // wallpaper Image is the source, which is also the `wallpaper` mode path
    // and the automatic fallback when capture fails.
    readonly property Item blurSource: (root.capture && root.capture.hasContent) ? root.capture : img

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
        visible: root.blurSource === img
    }

    // Holder for the reparented capture. Hidden (rather than the capture being
    // hidden) so the GaussianBlur can still source the capture through it: a
    // ShaderEffectSource renders its source item regardless of visibility.
    Item {
        id: captureHolder
        anchors.fill: parent
        visible: root.blurSource === root.capture
    }

    Component.onCompleted: {
        if (root.capture) {
            root.capture.parent = captureHolder;
            root.capture.anchors.fill = captureHolder;
        }
    }

    // Blurred copy, cross-faded over the sharp base. Qt5Compat's GaussianBlur
    // wraps its source in a SourceProxy, which passes a plain Image straight
    // through as a texture provider without hiding it -- so `img` stays on
    // screen as the sharp base while the blur samples the same texture.
    GaussianBlur {
        anchors.fill: parent
        source: root.blurSource
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
