import QtQuick
import "palettes" as Palettes
import "screens" as Screens

// The skin contract (see Task 8's stub, which this replaces): a skin drives
// the core singletons through session/sessions/palette/requestPower; it
// never talks to greetd directly (session.backend.available stands in for
// Greetd.available below, so this file never imports
// Quickshell.Services.Greetd itself), and it never reaches past
// Session/Sessions into Settings for anything privileged -- only cosmetic
// reads (which palette, branding text, the session-picker toggle) go
// straight to Settings from here and from screens/LogonDialog.qml.
Item {
    id: root
    property var session: null
    property var sessions: null
    // Read-only reflection of the palette this skin actually resolved, not
    // an input: nothing sets it from outside (shell.qml's contract only
    // ever assigns session/sessions/requestPower -- see shell.qml's
    // skinLoader.onLoaded), and picking it is this file's own job, driven
    // by Settings.palette rather than the caller.
    readonly property var palette: root.theme
    signal requestPower(string action)
    // Distinct from requestPower(action): requestPower fires an
    // already-decided systemctl action (poweroff/reboot/else-suspend --
    // see shell.qml's power()), and there is no "show me the choices"
    // case among those three. This fires the intent to see them; Task 11's
    // ShutDownDialog is the thing that turns an actual user pick into a
    // requestPower() call. Until Task 11 lands this is an inert seam: the
    // screens below emit it, nothing here consumes it yet.
    signal shutDownRequested()

    anchors.fill: parent

    Palettes.Luna { id: lunaPalette }
    // Gruvbox is Task 12; until then every registered palette name this
    // skin's meta.json advertises maps to the one real palette it ships.
    readonly property var _palettes: ({ luna: lunaPalette })
    // Settings here is a DIFFERENT singleton instance than the one
    // screens/LogonDialog.qml reads (per-directory registration -- see
    // that file's own note on this) -- harmless today only because this
    // file reads Settings.palette and LogonDialog.qml reads
    // Settings.config.sessions/branding, disjoint keys with no
    // computation shared between the two reads. Nothing enforces that
    // split; the same key read from both would risk observing two
    // different settle timings.
    readonly property var theme: root._palettes[Settings.palette] || lunaPalette

    // Sessions.ready starts false and settles asynchronously; treating an
    // empty-so-far list as fatal before it has ever settled would flash
    // this screen on every normal boot. Session.backend is assigned
    // synchronously by shell.qml (Component.onCompleted, before this
    // Loader's onLoaded runs), so availability does not need its own
    // separate settle flag the way Sessions.ready does.
    readonly property bool _greetdAvailable: !!root.session && !!root.session.backend
        && root.session.backend.available
    readonly property bool _hasSessions: !!root.sessions && root.sessions.ready
        && !!root.sessions.list && root.sessions.list.length > 0
    readonly property bool _fatal: !root._greetdAvailable
        || (!!root.sessions && root.sessions.ready && !root._hasSessions)

    Screens.LogonDialog {
        anchors.centerIn: parent
        visible: !root._fatal
        session: root.session
        sessions: root.sessions
        theme: root.theme
        onShutDownRequested: root.shutDownRequested()
    }

    Screens.SkinFatal {
        anchors.centerIn: parent
        visible: root._fatal
        theme: root.theme
        reason: !root._greetdAvailable
            ? "The login service is not available."
            : "No sessions are available to log into."
        onShutDownRequested: root.shutDownRequested()
    }
}
