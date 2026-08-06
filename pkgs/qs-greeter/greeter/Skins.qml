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
    // which is never copied into the installed package (see default.nix) --
    // so even if this env var ended up set on a deployed system, it stays
    // inert unless the target directory also carries that exact marker. The
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

    // { status: "ok", source, meta } | { status: "unknown" | "invalid" }.
    // "unknown" is no meta.json at that path at all (typo, unregistered
    // name); "invalid" is a meta.json that exists but cannot be trusted --
    // unparseable, or missing the "logon" capability every skin must
    // provide to be usable as the login surface. Both fall back, but only
    // "invalid" is a bug in a registered skin worth logging loudly.
    function _load(name) {
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

        Log.warn("skin '" + name + "' " + wanted.status
            + ", falling back to " + root.builtin);

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
