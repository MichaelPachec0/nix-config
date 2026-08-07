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
    // Injected by shell.qml's Loader.onLoaded, same as session/sessions
    // above: this file is loaded through a Loader whose `source` is a
    // runtime-computed absolute path, not a static `import`, so Quickshell
    // never registers skins/xp/ (or any directory under it) for bare
    // singleton access -- see shell.qml's own comment on this Loader for
    // the mechanism. Every bare `Settings`/`Log`/`CapsLock`/`GreeterState`
    // reference that used to live in this file and in screens/LogonDialog.qml
    // threw "ReferenceError: <name> is not defined" in production for
    // exactly this reason (confirmed with a standalone `qs -p` repro against
    // the built store package) while every headless dev/tests/ suite passed,
    // because those suites reach the skin through a directory import from an
    // entrypoint that sits right next to symlinks for these same singletons,
    // which DOES get scanned. Left null by default so a test can construct
    // this file directly without wiring every singleton (skin-smoke-test.qml
    // does exactly that, matching the existing session/sessions convention).
    property var settings: null
    property var log: null
    property var capsLock: null
    property var greeterState: null
    // Read-only reflection of the palette this skin actually resolved, not
    // an input: nothing sets it from outside (shell.qml's contract only
    // ever assigns session/sessions/requestPower -- see shell.qml's
    // skinLoader.onLoaded), and picking it is this file's own job, driven
    // by Settings.palette rather than the caller.
    readonly property var palette: root.theme
    signal requestPower(string action)

    // True while screens/ShutDownDialog.qml (the "Shut Down Windows"
    // modal) is up. Both LogonDialog.qml and SkinFatal.qml can ask for it
    // -- each fires its own `shutDownRequested()` when its "Shut Down..."
    // button is clicked -- but this file is the only thing that actually
    // owns the flag, so exactly one modal with one dimmed background ever
    // exists regardless of which screen asked. requestPower(action) above
    // is this skin's ONLY way out to shell.qml's power(): there is no
    // separate "shut down requested" signal exposed from this file at
    // all -- the choice made inside ShutDownDialog.qml is turned into a
    // requestPower(action) call right here, not re-exposed as its own
    // public seam the way it was (deliberately, as a placeholder) before
    // this dialog existed.
    property bool shutDownVisible: false

    anchors.fill: parent

    Palettes.Luna { id: lunaPalette }
    Palettes.Gruvbox { id: gruvboxPalette }
    // Every registered palette name this skin's meta.json advertises
    // (["luna", "gruvbox"]) maps to a real palette instance here. This is
    // one of THREE places this same palette set is written down, none of
    // which reference each other in code: meta.json's own "palettes" field
    // (decorative -- read by nothing, see Skins.qml's _load() for why),
    // qs-greeter.nix's hardcoded `skins.xp.palettes` inside defaults.json
    // (the allow-list SettingsMerge.js actually enforces against a
    // user-tier palette choice), and this map. Adding a palette means
    // editing all three; nothing catches it if you forget one.
    readonly property var _palettes: ({ luna: lunaPalette, gruvbox: gruvboxPalette })
    // root.settings is the SAME object shell.qml handed to root.session and
    // root.sessions -- one real Settings singleton, injected once, not a
    // per-directory copy (see the property declaration above for why a bare
    // reference cannot be used here instead). screens/LogonDialog.qml reads
    // Settings.config.sessions/branding through the same injected object, by
    // the same route (Skin.qml passes its own `settings` down, exactly as it
    // already does for `theme`) -- so unlike before, there is only ever one
    // instance in this whole tree, not four, and no risk of two reads
    // observing different settle timings.
    //
    // Guarded on `!!root.settings` because settings starts null until
    // shell.qml's Loader.onLoaded runs (the same brief window session/
    // sessions already have to tolerate below), and defaults to "luna" in
    // that window rather than logging a spurious "unknown palette ''"
    // warning for a value that just has not arrived yet.
    //
    // Settings.palette has already been validated against meta.json's
    // declared list by SettingsMerge.js before it reaches here in
    // production (unregistered names are dropped there -- see
    // SettingsMerge.js's skinSettings handling), so the actual fallback
    // path below should never fire from a real user-settings write. It
    // exists for the two paths that skip that validation: a test driving
    // Skin.qml directly (Settings/SettingsMerge.js validate the USER tier
    // only, not defaults.json), and defense against _palettes and
    // meta.json ever drifting out of sync. Falls back to Luna with a
    // warning rather than silently rendering unstyled (a missing key would
    // otherwise resolve every theme.* read to undefined).
    readonly property var theme: {
        var pal = (!!root.settings && root.settings.palette) || "luna";
        var p = root._palettes[pal];
        if (p) return p;
        if (root.log) root.log.warn("skins/xp: unknown palette '" + pal + "', falling back to luna");
        return lunaPalette;
    }

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

    // enabled/opacity both driven by shutDownVisible: enabled (a plain
    // QtQuick Item property, cascading to every descendant's input
    // regardless of that descendant's own local enabled state) is what
    // actually makes this screen non-interactive while the modal is up --
    // opacity is the visible half of "dimmed", enabled is the part that
    // makes it true rather than cosmetic. theme.faceDark-driven dimming
    // lives on the overlay Rectangle below, not here, so both screens
    // share exactly one dimming treatment.
    Screens.LogonDialog {
        id: logonDialog
        anchors.centerIn: parent
        visible: !root._fatal
        enabled: !root.shutDownVisible
        opacity: root.shutDownVisible ? 0.5 : 1.0
        session: root.session
        sessions: root.sessions
        theme: root.theme
        settings: root.settings
        capsLock: root.capsLock
        greeterState: root.greeterState
        onShutDownRequested: root.shutDownVisible = true
    }

    Screens.SkinFatal {
        id: skinFatalScreen
        anchors.centerIn: parent
        visible: root._fatal
        enabled: !root.shutDownVisible
        opacity: root.shutDownVisible ? 0.5 : 1.0
        theme: root.theme
        reason: !root._greetdAvailable
            ? "The login service is not available."
            : "No sessions are available to log into."
        onShutDownRequested: root.shutDownVisible = true
    }

    // Dims the whole skin area behind the modal (not just whichever of the
    // two screens above happens to be visible), in one paint-order slot
    // above both of them and below the modal itself. theme.faceDark, not a
    // literal -- this file is covered by the same "no literal colors"
    // rule as every other file under skins/.
    Rectangle {
        anchors.fill: parent
        visible: root.shutDownVisible
        color: root.theme.faceDark
        opacity: 0.35
    }

    Screens.ShutDownDialog {
        id: shutDownDialog
        anchors.centerIn: parent
        visible: root.shutDownVisible
        theme: root.theme
        onCancelled: root.shutDownVisible = false
        onRequestPower: function (action) {
            root.shutDownVisible = false;
            root.requestPower(action);
        }
    }

    // --- exposed for headless testing only (same convention as
    // LogonDialog.qml's testXxx aliases): lets a test reach the exact
    // child instances this file wires up, to drive the real
    // shutDownRequested() seam and observe enabled/opacity/visible on the
    // real objects, rather than re-deriving them from shutDownVisible. ---
    readonly property alias testLogonDialog: logonDialog
    readonly property alias testSkinFatal: skinFatalScreen
    readonly property alias testShutDownDialog: shutDownDialog
}
