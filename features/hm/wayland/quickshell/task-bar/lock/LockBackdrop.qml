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

    // The capture is used only in workspace backdrop mode, and only when it
    // holds a PRE-LOCK frame and is actually hosted in this surface's scene.
    // Anything else -- wallpaper mode, no capture, a frame that landed after
    // the lock, a view from a regenerated pool that has not been adopted yet
    // -- falls back to the wallpaper Image.
    readonly property Item blurSource: (LockConfig.backdropMode === "workspace" && root.capture && root.capture.preLockContent && root.capture.parent === captureHolder) ? root.capture : img

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

    // Host for the reparented capture, and the sharp cross-fade base when the
    // capture is in use -- mirrors img.visible on the wallpaper side. Hidden
    // only when the capture is not the blur source, in which case nothing is
    // sampling it anyway.
    Item {
        id: captureHolder
        anchors.fill: parent
        visible: root.blurSource === root.capture
    }

    // Adopt the capture whenever it changes, not just once at creation: the
    // `capture` binding re-evaluates (monitor hotplug regenerates the whole
    // pool), and an unadopted view would be selected as the blur source while
    // sitting outside this scene -- a black backdrop.
    function _adoptCapture() {
        if (root.capture && root.capture.parent !== captureHolder) {
            root.capture.parent = captureHolder;
            root.capture.anchors.fill = captureHolder;
        }
    }

    onCaptureChanged: root._adoptCapture()
    Component.onCompleted: root._adoptCapture()

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
