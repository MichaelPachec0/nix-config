pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Skin registry and fallback chain.
//
// A skin is arbitrary QML running before authentication, so skins may only be
// registered from Nix: the set of names this resolves is exactly the set of
// directories shipped under skins/ inside this package (default.nix copies
// the whole greeter/ tree, skins/ included, into the store). The user tier
// picks among registered names via Settings.skinName; it can never supply a
// path -- SettingsMerge.js already refuses any "skin" value that is not a key
// of the Nix-authored registry. Three rungs, because the one extension point
// that touches pre-auth code needs a hard floor: requested skin -> built-in
// xp -> CoreFatal (rendered by shell.qml when resolve() reports no usable
// skin at all).
Singleton {
    id: root

    readonly property string builtin: "xp"

    // QSG_SKIN_ROOT lets the test suite point resolve() at
    // dev/fixtures/skins instead of the real skins/ tree, so the "broken"
    // fixture is reachable at all. It is gated on a marker file
    // (dev/fixtures/skins/dev-only-marker) that ships only inside dev/,
    // which is never copied into the installed package (see default.nix).
    // This is an accident guard, not a security boundary: it stops a stray
    // or accidentally-inherited QSG_SKIN_ROOT from doing anything on a
    // deployed system, because the production skins/ tree never carries
    // the marker. It does NOT stop a capable attacker -- anyone with
    // enough access to set an env var on the greeter's own process could
    // just as easily create the marker file too, at which point this gate
    // offers nothing extra. The actual barrier against arbitrary QML
    // execution is the skin-name validation in _validName()/_load() below,
    // which resolve() applies no matter where root_ ends up pointing. The
    // real launcher (qs-greeter.nix wrapperPackage) never sets this var.
    readonly property string _envRoot: Quickshell.env("QSG_SKIN_ROOT") || ""
    readonly property bool _envRootTrusted: root._envRoot !== ""
        && root._readTextBlocking(root._envRoot + "/dev-only-marker") !== null
    readonly property string root_: (root._envRootTrusted ? root._envRoot : "")
        || Qt.resolvedUrl("skins").toString().replace("file://", "")

    function provides(meta, capability) {
        return !!meta && Array.isArray(meta.provides)
            && meta.provides.indexOf(capability) >= 0;
    }

    // A skin name is an identifier, not a path: lowercase letters, digits,
    // hyphen, underscore, bounded length. An allow-list on shape rather
    // than a deny-list of known-bad sequences, because a deny-list only
    // stops the traversal patterns someone thought to block ("..", a
    // leading "/") and misses the rest -- a URL scheme ("file:", "qrc:"),
    // an embedded null byte, a bare "~", an over-long string. This is what
    // actually keeps _load() from ever constructing a path outside skins/,
    // independent of any caller: SettingsMerge.js already checks a
    // requested skin name against the Nix-built registry before it can
    // reach resolve(), but that is a second, independent barrier, not a
    // substitute for this one. A future caller that forgets the registry
    // check (a Nix option letting a host register additional skin packages
    // would be exactly that shape of caller -- programs.qsGreeter.skins.extra
    // was one such option, removed rather than fixed because nothing in
    // this repo ever set it and actually wiring it up meant building a
    // merged skins/ tree Skins.qml's root_ never learns about today) must
    // not be able to walk a skin name into a path escape.
    function _validName(name) {
        return typeof name === "string" && /^[a-z0-9_-]{1,32}$/.test(name);
    }

    // Reads a small file synchronously. Quickshell disables XMLHttpRequest's
    // file:// reads by default (QML_XHR_ALLOW_FILE_READ), and setting that
    // flag for the whole process just to read meta.json would hand every
    // skin -- including a broken or malicious one -- the same ability. A
    // throwaway FileView with blockLoading does the same job without that:
    // calling .text() before the file has loaded blocks until the read
    // settles (success or failure), which is exactly the synchronous answer
    // resolve() needs. The block happens INSIDE the .text() call itself, not
    // before it -- checking the `loaded` property first and skipping .text()
    // when it still reads false (as an earlier version of this function did)
    // never triggers the wait at all and always looks like a missing file,
    // proven out with a standalone qs -p repro. A fresh FileView per call
    // because blockLoading only blocks a path's FIRST load -- reusing one
    // instance across different paths would silently stop blocking after
    // the first read (see FileView.blockLoading's docs). `path` is assigned
    // as a plain property after construction, never interpolated into the
    // dynamic QML source, so a skin name can never inject QML here even in
    // principle.
    function _readTextBlocking(path) {
        var fv = Qt.createQmlObject(
            'import Quickshell.Io; FileView { blockLoading: true; printErrors: false }',
            root, "qs-greeter-skins-probe");
        fv.path = path;
        var text = null;
        try { text = fv.text(); } catch (e) { text = null; }
        if (!fv.loaded) text = null;
        fv.destroy();
        return text;
    }

    // { status: "ok", source, meta }
    // | { status: "unknown" | "invalid" | "malformed" }.
    // "malformed" is a name that fails _validName() -- rejected before any
    // path is built from it, so it can never reach root.root_ + "/" + name.
    // "unknown" is a well-formed name with no meta.json at that path
    // (typo, unregistered name); "invalid" is a meta.json that exists but
    // cannot be trusted -- unparseable, or missing the "logon" capability
    // every skin must provide to be usable as the login surface. All three
    // fall back, but "invalid" and "malformed" are each a bug (in a
    // registered skin, or in whatever produced the name) worth logging
    // loudly; "unknown" is ordinary typo/unregistered-name noise.
    // NOTE for anyone editing a skin's meta.json: its own "palettes" and
    // "defaultPalette" fields (and any "provides" entry beyond "logon") are
    // read by nothing at all -- this function only ever checks provides()
    // for "logon" a few lines down. The palette allow-list actually
    // enforced at runtime is qs-greeter.nix's hardcoded
    // `skins.xp.palettes = ["luna" "gruvbox"]` inside defaults.json (what
    // SettingsMerge.js validates a user-tier palette choice against), and
    // the palette NAMES that resolve to an actual instance live in
    // skins/xp/Skin.qml's `_palettes` map. All three have to move together
    // for a new palette to actually work; nothing enforces that
    // automatically, and meta.json itself cannot hold this note (plain
    // JSON, no comment syntax) -- hence it living here instead, in the one
    // file that actually reads meta.json.
    function _load(name) {
        if (!root._validName(name)) return { status: "malformed" };
        var dir = root.root_ + "/" + name;
        var text = root._readTextBlocking(dir + "/meta.json");
        if (text === null) return { status: "unknown" };

        var meta;
        try {
            meta = JSON.parse(text);
        } catch (e) {
            Log.warn("skin '" + name + "' metadata unparseable: " + e);
            return { status: "invalid" };
        }
        if (!root.provides(meta, "logon")) {
            Log.warn("skin '" + name + "' does not provide logon");
            return { status: "invalid" };
        }
        return { status: "ok", source: dir + "/Skin.qml", meta: meta };
    }

    function resolve(name) {
        var wanted = root._load(name);
        if (wanted.status === "ok")
            return { source: wanted.source, meta: wanted.meta, reason: "ok" };

        if (wanted.status === "malformed") {
            // Not a typo -- a name that fails the shape check at all is a
            // sign something upstream is wrong (or hostile), so this is
            // logged as an error, not the routine warning an unregistered
            // name gets. The rejected name is logged as-is: it is already
            // known not to be a path (that is what "malformed" means), so
            // there is nothing here for it to traverse into.
            Log.error("skin name '" + name + "' rejected (not a valid "
                + "identifier), falling back to " + root.builtin);
        } else {
            Log.warn("skin '" + name + "' " + wanted.status
                + ", falling back to " + root.builtin);
        }

        if (name === root.builtin) {
            // The built-in itself failed; there is nowhere left to fall to.
            Log.error("built-in skin '" + root.builtin
                + "' failed to load; no usable skin");
            return { source: "", meta: null, reason: "fatal" };
        }

        var fb = root._load(root.builtin);
        if (fb.status === "ok")
            return { source: fb.source, meta: fb.meta, reason: wanted.status };

        Log.error("built-in skin '" + root.builtin
            + "' failed to load; no usable skin");
        return { source: "", meta: null, reason: "fatal" };
    }
}
