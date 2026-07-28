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

    // This surface's output name, and the callback that publishes our capture
    // holder to Lock.qml's registry under that name.
    //
    // Ownership is INVERTED on purpose: this backdrop never looks a capture up
    // by name and never reparents one in. It only advertises "the holder for
    // output <screenName> is this Item", and Lock.qml's pool delegate -- whose
    // own `modelData` is stable -- parents ITSELF in. A backdrop therefore can
    // never touch another output's view.
    //
    // The earlier design had each backdrop resolve captureFor(screen.name) and
    // reparent the result in. That is unfixable on multi-monitor: while the
    // lock surfaces are being built `surface.screen` is briefly unsettled, so a
    // surface resolves to its NEIGHBOUR's view and steals it out of the holder
    // that owned it -- the victim never recovering, because its own `capture`
    // never changed and so nothing re-ran adoption. Worse, a Qt
    // ShaderEffectSource reparents its sourceItem whenever that item has no
    // parent (exactly the state of a fresh pool view), so a neighbouring
    // GaussianBlur could claim one too; re-adopting on parentChanged then
    // ping-ponged the item between surfaces forever.
    property string screenName: ""
    property var registerHolder: null

    // Restate our claim on every change, including to "" -- Lock.qml rebuilds
    // the whole name->holder map from the live claims, so a stale or
    // transiently-wrong claim is corrected rather than accumulated.
    function _publishHolder() {
        if (root.registerHolder)
            root.registerHolder(root.screenName, captureHolder);
    }
    onScreenNameChanged: root._publishHolder()
    Component.onDestruction: {
        if (root.registerHolder)
            root.registerHolder("", captureHolder); // retire on monitor unplug
    }

    // Whatever the pool has parented into us, or null. Derived from our OWN
    // children rather than from a lookup, so this can never name an item that
    // lives in another surface. `children` notifies, so it stays live as the
    // pool parents in and (on unlock) tears the views down.
    readonly property Item capture: captureHolder.children.length > 0 ? captureHolder.children[0] : null

    // The capture is used only in workspace mode, and only when it holds a
    // PRE-LOCK frame. Anything else -- wallpaper mode, no capture yet, or a
    // frame that only landed after the lock engaged (which would be black) --
    // falls back to the wallpaper Image.
    readonly property Item blurSource: (LockConfig.backdropMode === "workspace" && root.capture
        && root.capture.preLockContent) ? root.capture : img

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

    // Host for the pool's view, and the sharp cross-fade base when the capture
    // is in use -- mirrors img.visible on the wallpaper side.
    Item {
        id: captureHolder
        anchors.fill: parent
        visible: root.blurSource === root.capture
    }

    Component.onCompleted: root._publishHolder()


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
