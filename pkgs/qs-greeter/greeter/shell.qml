import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "screens" as Screens

ShellRoot {
    id: shellRoot

    Component.onCompleted: {
        Session.backend = greetdBackend;
        if (!greetdBackend.available)
            Log.error("greetd is not available (GREETD_SOCK unset)");
    }

    GreetdBackend { id: greetdBackend }

    // A plain property binding, not a one-shot read in Component.onCompleted:
    // Settings.skinName is itself reactive (config.skin || "xp"), so this
    // re-evaluates on its own once Settings finishes loading, and again if
    // the user tier's skin choice changes later -- no explicit readyChanged
    // handling needed here, unlike the async-settling traps elsewhere in
    // this codebase where a value was read once and never revisited.
    // Settings.skinName defaults to "xp" even before Settings.ready, which
    // happens to equal the built-in fallback, so there is nothing to show
    // before the first settle in the common case.
    property var skinResolution: Skins.resolve(Settings.skinName)

    // Backdrop.qml declares its own `required property var modelData`; Variants
    // sets that property directly from each model item, so the delegate here
    // must NOT redeclare or bind it itself. `Screens.Backdrop { modelData:
    // modelData }` would be a self-referential binding (the property reading
    // itself) and never receive the actual screen.
    Variants {
        model: Quickshell.screens
        Screens.Backdrop {}
    }

    // Latches true the first time the walking-skeleton auto-launch actually
    // fires, so launch() is called at most once per shell lifetime no matter
    // how many times _maybeLaunch() is re-entered (Session state settling,
    // Sessions finishing its load, or both in either order). Without this,
    // a stray re-entry (e.g. Session cycling back through "ready") would call
    // backend.launch() a second time on top of an already-launching session.
    property bool _autoLaunched: false

    // Ready to launch requires BOTH Session having reached "ready" (greetd's
    // side is done) AND Sessions having settled (the wrapper's sessions.json
    // FileView has loaded or failed -- see Sessions.qml). Gating on Session
    // state alone races: if greetd reaches "ready" before the session list
    // has loaded, Sessions.list is still its initial empty array and this
    // would silently no-op forever, since onStateChanged only re-fires on
    // Session's own state changes, never on Sessions arriving later.
    function _maybeLaunch() {
        if (shellRoot._autoLaunched) return;
        if (Session.state !== "ready") return;
        if (!Sessions.ready) return;
        if (Sessions.list.length === 0) return;
        shellRoot._autoLaunched = true;
        Session.launch(Sessions.list[0]);
    }

    PanelWindow {
        id: login
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: greetdBackend.available
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "qs-greeter:login"
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        Loader {
            id: skinLoader
            anchors.fill: parent
            source: shellRoot.skinResolution.source
            onStatusChanged: if (status === Loader.Error)
                Log.error("skin failed to instantiate: " + shellRoot.skinResolution.source);
            onLoaded: {
                item.session = Session;
                item.sessions = Sessions;
                item.requestPower.connect(shellRoot.power);
            }
        }

        // Ready -> launch the first session. Task 10 adds the picker.
        Connections {
            target: Session
            function onStateChanged() { shellRoot._maybeLaunch(); }
        }

        Connections {
            target: Sessions
            function onReadyChanged() { shellRoot._maybeLaunch(); }
        }
    }

    // The last rung of the fallback chain. CoreFatal.qml is a PanelWindow in
    // its own right (its own screen anchors and layer-shell namespace), so it
    // is declared as a sibling here rather than nested inside `login` --
    // nesting a PanelWindow inside another PanelWindow's item tree and giving
    // it `anchors.fill: parent` does not work: PanelWindow's `anchors` object
    // is the layer-shell edge-anchor API (booleans per screen edge), not
    // QtQuick.Item's anchors, and QML rejects the unknown `fill` property at
    // load time (confirmed with a standalone qs -p repro). Shown whenever the
    // Loader failed to instantiate the resolved skin, or resolve() itself
    // could not find any usable skin at all (reason "fatal" -- the built-in
    // xp skin is broken too, so there is nowhere left to fall back to).
    Screens.CoreFatal {
        visible: skinLoader.status === Loader.Error
            || shellRoot.skinResolution.reason === "fatal"
        modelData: login.screen
        reason: "No usable skin could be loaded."
    }

    function power(action) {
        var argv = action === "poweroff" ? ["systemctl", "poweroff"]
                 : action === "reboot"   ? ["systemctl", "reboot"]
                 : ["systemctl", "suspend"];
        Log.info("power action: " + action);
        powerProc.command = argv;
        powerProc.running = true;
    }

    Process { id: powerProc }
}
