import QtQuick
import Quickshell
import "SettingsMerge.js" as M

ShellRoot {
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (JSON.stringify(got) === JSON.stringify(want)) { pass++; }
            else console.log("MERGE-TEST CASE FAIL: " + name
                + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }
        function warned(name, res, needle) {
            total++;
            var hit = res.warnings.some(function (w) { return w.indexOf(needle) >= 0; });
            if (hit) { pass++; }
            else console.log("MERGE-TEST CASE FAIL: " + name
                + " expected a warning containing " + needle
                + " got=" + JSON.stringify(res.warnings));
        }

        var defaults = {
            skin: "xp",
            skinSettings: { xp: { palette: "luna" } },
            backdrop: { kind: "color", color: "#3A6EA5", image: null, fit: "cover" },
            sessions: { picker: true, default: null },
            optionsExpanded: false,
            rememberLastUser: true,
            branding: { title: "Log On to Windows", subtitle: "Microsoft Windows XP  Professional" }
        };
        var opts = { precedence: "user", skins: { xp: { palettes: ["luna", "gruvbox"] } } };

        // missing file -> defaults, no warnings
        var r = M.merge(defaults, null, opts);
        check("missingFile", r.config.skinSettings.xp.palette, "luna");
        check("missingFileQuiet", r.warnings.length, 0);

        // valid override wins
        r = M.merge(defaults, JSON.stringify({ version: 1, skinSettings: { xp: { palette: "gruvbox" } } }), opts);
        check("paletteOverride", r.config.skinSettings.xp.palette, "gruvbox");

        // precedence = nix ignores the file entirely
        r = M.merge(defaults, JSON.stringify({ version: 1, skin: "xp", optionsExpanded: true }),
                    { precedence: "nix", skins: opts.skins });
        check("precedenceNix", r.config.optionsExpanded, false);

        // corrupt JSON -> whole tier discarded, warned
        r = M.merge(defaults, "{ not json", opts);
        check("corruptFalls Back", r.config.skin, "xp");
        warned("corruptWarns", r, "unparseable");

        // non-object top level -> discarded
        r = M.merge(defaults, "[1,2,3]", opts);
        warned("nonObject", r, "not an object");

        // wrong version -> discarded
        r = M.merge(defaults, JSON.stringify({ version: 2, optionsExpanded: true }), opts);
        check("badVersion", r.config.optionsExpanded, false);
        warned("badVersionWarns", r, "version");

        // privileged key -> dropped loudly, rest of the file still applies
        r = M.merge(defaults, JSON.stringify({
            version: 1, optionsExpanded: true,
            sessions: { picker: false, shells: ["/bin/sh"] }
        }), opts);
        check("privilegedDropped", r.config.sessions.shells, undefined);
        check("privilegedSiblingKept", r.config.sessions.picker, false);
        check("privilegedOtherKeysKept", r.config.optionsExpanded, true);
        warned("privilegedWarns", r, "privileged");

        // unknown key -> dropped, warned, rest applies
        r = M.merge(defaults, JSON.stringify({ version: 1, wat: 1, optionsExpanded: true }), opts);
        check("unknownDropped", r.config.wat, undefined);
        check("unknownSiblingKept", r.config.optionsExpanded, true);
        warned("unknownWarns", r, "unknown");

        // wrong type -> that key only falls back
        r = M.merge(defaults, JSON.stringify({ version: 1, optionsExpanded: "yes", rememberLastUser: false }), opts);
        check("wrongTypeDropped", r.config.optionsExpanded, false);
        check("wrongTypeSiblingKept", r.config.rememberLastUser, false);

        // unknown skin -> dropped
        r = M.merge(defaults, JSON.stringify({ version: 1, skin: "aqua" }), opts);
        check("unknownSkin", r.config.skin, "xp");
        warned("unknownSkinWarns", r, "skin");

        // unknown palette for a known skin -> dropped
        r = M.merge(defaults, JSON.stringify({ version: 1, skinSettings: { xp: { palette: "neon" } } }), opts);
        check("unknownPalette", r.config.skinSettings.xp.palette, "luna");

        // backdrop image must be a basename
        r = M.merge(defaults, JSON.stringify({ version: 1, backdrop: { kind: "image", image: "../../etc/shadow" } }), opts);
        check("traversalRejected", r.config.backdrop.image, null);
        check("traversalKindReverts", r.config.backdrop.kind, "color");
        warned("traversalWarns", r, "basename");

        // a plain basename is accepted
        r = M.merge(defaults, JSON.stringify({ version: 1, backdrop: { kind: "image", image: "bliss.jpg" } }), opts);
        check("basenameAccepted", r.config.backdrop.image, "bliss.jpg");
        check("basenameKind", r.config.backdrop.kind, "image");

        // enum validation on fit
        r = M.merge(defaults, JSON.stringify({ version: 1, backdrop: { fit: "diagonal" } }), opts);
        check("badEnum", r.config.backdrop.fit, "cover");

        console.log("MERGE-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }
}
