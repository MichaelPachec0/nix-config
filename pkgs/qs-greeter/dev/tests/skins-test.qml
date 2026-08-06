import QtQuick
import Quickshell

// Skins.qml is a same-directory symlink to ../../greeter/Skins.qml (see
// SettingsMerge.js and screens/Settings.qml for the same technique).
// Quickshell sandboxes QML module imports to the entrypoint's own directory
// -- `import "../../greeter"` fails with "Module path ... is outside of the
// config folder" -- so the singleton is used bare below, exactly as
// shell.qml uses it, no import alias and no copy of the greeter's code.
ShellRoot {
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("SKINS-TEST CASE FAIL: " + name + " got=" + got + " want=" + want);
        }

        var r = Skins.resolve("xp");
        check("knownSkinOk", r.reason, "ok");
        check("knownSkinSource", r.source.indexOf("skins/xp/Skin.qml") >= 0, true);
        check("providesLogon", Skins.provides(r.meta, "logon"), true);
        var knownXpSource = r.source;

        r = Skins.resolve("aqua");
        check("unknownFallsBack", r.reason, "unknown");
        check("unknownUsesDefault", r.source.indexOf("skins/xp/Skin.qml") >= 0, true);

        r = Skins.resolve("broken");
        check("brokenReason", r.reason, "invalid");
        check("brokenFallsBackToXp", r.source.indexOf("skins/xp/Skin.qml") >= 0, true);
        check("brokenLacksLogon", Skins.provides(r.meta, "logon"), true);

        // Traversal / injection defense: resolve() must be safe on its own
        // terms, independent of the registry check SettingsMerge.js already
        // does before a name from the user tier can reach here. Every case
        // below must fall back to xp AND must not leak into the returned
        // source path -- checking only the reason code would miss the actual
        // bug this guards against (a right-looking reason next to an escaped
        // path). Each case asserts r.source is byte-for-byte identical to
        // the known-good xp source captured above, which is strictly
        // stronger than an indexOf/substring check: a crafted name that
        // merely got "skins/xp/Skin.qml" to appear somewhere inside a
        // longer, still-escaped path would still fail this.
        var overLength = "";
        for (var i = 0; i < 40; i++) overLength += "a";

        var traversalCases = [
            ["dotdot", "../evil"],
            ["deepDotdot", "../../../../tmp/x"],
            ["absolute", "/etc/passwd"],
            ["fileScheme", "file:///tmp/x"],
            ["qrcScheme", "qrc:/x"],
            ["empty", ""],
            ["nullByte", "evil\u0000name"],
            ["overLength", overLength]
        ];

        for (var t = 0; t < traversalCases.length; t++) {
            var label = traversalCases[t][0];
            var name = traversalCases[t][1];
            var tr = Skins.resolve(name);
            check(label + "Reason", tr.reason, "malformed");
            check(label + "SourceIsExactlyXp", tr.source, knownXpSource);
            check(label + "NoTraversal", tr.source.indexOf("..") < 0, true);
        }

        console.log("SKINS-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }
}
