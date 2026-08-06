pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The session list is produced by the wrapper before the UI starts (see
// sessions-parse.sh). It is read-only here: argv must never originate from
// anything the user tier can write.
Singleton {
    id: root

    readonly property string path: Quickshell.env("QSG_SESSIONS")
        || "/run/qs-greeter/sessions.json"
    property var list: []
    property bool ready: false

    function byName(name) {
        for (var i = 0; i < list.length; i++)
            if (list[i].name === name) return list[i];
        return null;
    }

    FileView {
        path: root.path
        onLoaded: {
            try {
                var parsed = JSON.parse(text());
                root.list = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                Log.error("sessions.json unparseable: " + e);
                root.list = [];
            }
            root.ready = true;
            Log.info("sessions: " + root.list.length + " entries");
        }
        onLoadFailed: {
            Log.error("sessions.json missing at " + root.path);
            root.list = [];
            root.ready = true;
        }
    }
}
