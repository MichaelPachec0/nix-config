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

        r = Skins.resolve("aqua");
        check("unknownFallsBack", r.reason, "unknown");
        check("unknownUsesDefault", r.source.indexOf("skins/xp/Skin.qml") >= 0, true);

        r = Skins.resolve("broken");
        check("brokenReason", r.reason, "invalid");
        check("brokenFallsBackToXp", r.source.indexOf("skins/xp/Skin.qml") >= 0, true);
        check("brokenLacksLogon", Skins.provides(r.meta, "logon"), true);

        console.log("SKINS-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }
}
