import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "screens" as Screens
import "PrimaryOutput.js" as PrimaryOutput

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

    // Set true the instant ANY per-output Loader below reports Loader.Error
    // and never reset: once a skin instance has failed to instantiate at all
    // (a syntax/type error in the resolved QML, distinct from
    // Skins.resolve() itself reporting reason "fatal" for a registry-level
    // failure), CoreFatal must come up on every output, not just the one
    // whose Loader happened to error first -- the whole point of F2/F3 below
    // is that a failure state must never be visible on some outputs and
    // silently blank on others.
    property bool anySkinLoadFailed: false

    // QSG_PRIMARY_OUTPUT (programs.qsGreeter.primaryOutput) names the one
    // output whose window is allowed to hold WlrKeyboardFocus.Exclusive.
    // Quickshell's own docs for that enum value are blunt about why only one
    // surface may ever claim it: "Exclusive access to the keyboard, locking
    // out all other windows." Handing it to more than one layer-shell
    // surface at once does not average out or "share" the keyboard -- some
    // compositor-internal arbitration this codebase has no way to observe
    // without a live session picks exactly one winner, and which one wins is
    // not something this fix can test under its actual constraints (no
    // nested compositor, no taking focus). So it is avoided by construction
    // instead: every output still renders the full skin (see the Variants
    // below), but only isPrimaryScreen() ever returns true for more than one
    // of them being asked, and only that one output's window sets Exclusive.
    //
    // The screens[0] fallback (used both when this is unset, and when it
    // names an output that is not currently present -- see PrimaryOutput.js)
    // can never resolve to a disabled output: Quickshell.screens is Qt's
    // own QGuiApplication::screens() list, sourced from the wl_output
    // globals the compositor currently advertises as connected, so a
    // genuinely disabled output is never a member of this list at all.
    // What it CAN resolve to is an output the user cannot currently see --
    // a closed laptop lid the compositor still keeps enabled being the
    // concrete case that motivated this whole fix -- and that is exactly
    // the case the per-output rendering below covers: the dialog still
    // renders there, it simply does not hold the keyboard, so setting
    // QSG_PRIMARY_OUTPUT to the connector name of whichever output is
    // actually reachable after a dock/lid change removes the remaining
    // ambiguity for hosts that need it. If that named output is later
    // disconnected (the same host undocked), the fallback engages instead
    // of leaving no output holding the keyboard at all.
    readonly property string primaryOutputName: Quickshell.env("QSG_PRIMARY_OUTPUT") || ""

    // The actual decision (including the "named output not currently
    // present falls back to screens[0], never to no claimant at all" rule)
    // lives in PrimaryOutput.js, pure JS with no Quickshell.screens
    // dependency of its own so it is unit-testable headlessly -- see that
    // file's own comment.
    function isPrimaryScreen(screen) {
        return PrimaryOutput.isPrimary(Quickshell.screens, shellRoot.primaryOutputName, screen);
    }

    // Backdrop.qml declares its own `required property var modelData`; Variants
    // sets that property directly from each model item, so the delegate here
    // must NOT redeclare or bind it itself. `Screens.Backdrop { modelData:
    // modelData }` would be a self-referential binding (the property reading
    // itself) and never receive the actual screen.
    Variants {
        model: Quickshell.screens
        Screens.Backdrop {}
    }

    // One login window per output, not pinned to Quickshell.screens[0]: a
    // single fixed screen left every OTHER output showing nothing but the
    // plain backdrop above whenever that fixed screen was not the one
    // actually in front of the user -- docked with the lid closed is the
    // concrete case that surfaced this (the internal panel can stay enabled
    // and still sort first in Quickshell.screens while physically
    // unreachable). Rendering the skin on every output instead means the
    // dialog is visible wherever the user actually is; see
    // shellRoot.isPrimaryScreen() above for how exactly one of them still
    // gets to hold the keyboard.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: login
            required property var modelData
            screen: modelData
            // NOT gated on greetdBackend.available: that used to hide this
            // entire window -- the login dialog AND the "login service is
            // not available" fallback screen alike -- in exactly the case
            // the fallback screen exists to explain. Skin.qml's own _fatal
            // logic already decides, reactively, whether to show
            // LogonDialog or SkinFatal; this window must stay visible
            // either way so that decision is ever seen.
            visible: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: shellRoot.isPrimaryScreen(modelData)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "qs-greeter:login"
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            Loader {
                id: skinLoader
                anchors.fill: parent
                source: shellRoot.skinResolution.source
                onStatusChanged: if (status === Loader.Error) {
                    Log.error("skin failed to instantiate: " + shellRoot.skinResolution.source);
                    shellRoot.anySkinLoadFailed = true;
                }
                onLoaded: {
                    item.session = Session;
                    item.sessions = Sessions;
                    // Settings/Log/CapsLock/GreeterState are singletons
                    // greeter/ itself can read bare (this file lives in the
                    // directory Quickshell's scanner actually visits), but
                    // the skin loaded above cannot: it is reached only
                    // through this Loader's dynamically-computed `source`
                    // string, never through a static `import` anywhere in
                    // the scanned tree, so Quickshell's per-directory
                    // singleton scan (see scan.cpp's scanQmlFile -- it
                    // discovers directories to register by walking textual
                    // `import` statements starting from this file, and a
                    // Loader.source assignment is invisible to that walk)
                    // never runs for skins/xp/ or any directory under it.
                    // A same-directory symlink to e.g. Settings.qml does
                    // not fix that: the file resolves fine, but nothing
                    // ever registers it as an importable singleton there,
                    // so a bare `Settings.foo` reference inside the skin
                    // throws "ReferenceError: Settings is not defined" at
                    // runtime -- confirmed with a standalone `qs -p` repro
                    // against the built store package. These four are
                    // handed down the same way session/sessions already
                    // are, and Skin.qml re-exposes them to its own screens
                    // exactly as it already does for `theme`.
                    item.settings = Settings;
                    item.log = Log;
                    item.capsLock = CapsLock;
                    item.greeterState = GreeterState;
                    item.requestPower.connect(shellRoot.power);
                }
            }
        }
    }

    // The last rung of the fallback chain, one per output for the same
    // reason as the login window above: shown only when there is no usable
    // skin at all, but when that happens it must not be silently absent on
    // whichever output the user is actually looking at. CoreFatal.qml is a
    // PanelWindow in its own right (its own screen anchors and layer-shell
    // namespace), so it is declared as a sibling here rather than nested
    // inside `login` -- nesting a PanelWindow inside another PanelWindow's
    // item tree and giving it `anchors.fill: parent` does not work:
    // PanelWindow's `anchors` object is the layer-shell edge-anchor API
    // (booleans per screen edge), not QtQuick.Item's anchors, and QML
    // rejects the unknown `fill` property at load time (confirmed with a
    // standalone qs -p repro).
    Variants {
        model: Quickshell.screens
        Screens.CoreFatal {
            visible: shellRoot.anySkinLoadFailed
                || shellRoot.skinResolution.reason === "fatal"
            reason: "No usable skin could be loaded."
            keyboardExclusive: shellRoot.isPrimaryScreen(modelData)
        }
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
