pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsMerge.js" as M

// Merged view of the two configuration tiers. Nix writes defaults.json into
// the store next to this file; the user tier is a group-writable JSON that may
// carry cosmetic keys only (see SettingsMerge.js for why).
Singleton {
    id: root

    readonly property string defaultsPath: Quickshell.env("QSG_DEFAULTS")
        || (Quickshell.env("QSG_CONFIG") || ".") + "/defaults.json"
    readonly property string userPath: Quickshell.env("QSG_USER_FILE")
        || "/var/lib/qs-greeter/settings.json"
    readonly property string backdropDir: Quickshell.env("QSG_BACKDROP_DIR")
        || "/var/lib/qs-greeter/backdrops"
    readonly property string precedence: Quickshell.env("QSG_PRECEDENCE") || "user"

    property bool ready: false
    property var config: ({})
    property var skinRegistry: ({})

    readonly property string skinName: config.skin || "xp"
    readonly property string palette: (config.skinSettings
        && config.skinSettings[skinName]
        && config.skinSettings[skinName].palette) || "luna"
    readonly property string backdropPath:
        (config.backdrop && config.backdrop.kind === "image" && config.backdrop.image)
            ? backdropDir + "/" + config.backdrop.image
            : ""

    // Each FileView settles independently once it has either loaded or
    // failed to load -- a missing user file is normal first-boot behavior,
    // not an error, and must not block the greeter from coming up. `ready`
    // must not flip true until BOTH have settled: recomputing off just
    // whichever view happens to fire first silently merges a defaults-only
    // config whenever the user file's async load loses the race (its
    // FileView.text() reads back "" before it has settled, which
    // SettingsMerge.js correctly treats as "no user file" rather than an
    // error). That merge would then latch ready = true before the
    // corrected recompute lands, and since bool true -> true does not
    // re-fire readyChanged, anything gating on "ready" as a one-shot signal
    // -- this test, and the real UI later -- would never learn the config
    // changed underneath it.
    property bool _defaultsSettled: false
    property bool _userSettled: false

    function _settle() {
        if (!(root._defaultsSettled && root._userSettled)) return;
        root._recompute();
        root.ready = true;
    }

    function _recompute() {
        var defaults;
        try {
            defaults = JSON.parse(defaultsFile.text());
        } catch (e) {
            // Cannot happen with a Nix-generated file, but a greeter that
            // cannot parse its own defaults must still render something.
            Log.error("defaults.json unreadable (" + e + "), using built-ins");
            defaults = {
                skin: "xp",
                skinSettings: { xp: { palette: "luna" } },
                backdrop: { kind: "color", color: "#3A6EA5", image: null, fit: "cover" },
                sessions: { picker: true, default: null },
                optionsExpanded: false,
                rememberLastUser: true,
                branding: { title: "Log On to Windows",
                            subtitle: "Microsoft Windows XP  Professional" }
            };
        }
        root.skinRegistry = defaults.skins || { xp: { palettes: ["luna", "gruvbox"] } };

        var userText = null;
        try { userText = userFile.text(); } catch (e) { userText = null; }

        var res = M.merge(defaults, userText,
            { precedence: root.precedence, skins: root.skinRegistry });
        res.warnings.forEach(function (w) { Log.warn("settings: " + w); });
        root.config = res.config;
        Log.info("settings ready: skin=" + root.skinName + " palette=" + root.palette);
    }

    FileView {
        id: defaultsFile
        path: root.defaultsPath
        onLoaded: {
            root._defaultsSettled = true;
            root._settle();
        }
        onLoadFailed: {
            Log.error("defaults.json missing at " + root.defaultsPath);
            root._defaultsSettled = true;
            root._settle();
        }
    }

    FileView {
        id: userFile
        path: root.userPath
        onLoaded: {
            root._userSettled = true;
            root._settle();
        }
        onLoadFailed: {
            root._userSettled = true;
            root._settle();
        }
    }
}
