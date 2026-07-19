pragma ComponentBehavior: Bound
import QtQml
import Quickshell

// Per-player MPRIS TrackList/Playlists access via lib/mpris-extra.sh (busctl).
// Quickshell's Mpris service is Player-only; this polls the queue/playlists of
// `bus` while the matching tab wants them, exposes the lists + capability flags,
// and provides action methods. A cheap `caps` poll runs while the popup is open
// so the tabs can appear before the (heavier) full fetch runs.
QtObject {
    id: ex

    property string bus: ""
    property bool popupOpen: false
    property bool queueWants: false
    property bool playlistsWants: false

    property var caps: ({
            "queue": 0,
            "playlists": 0
        })
    readonly property bool supportsQueue: ex.bus !== "" && ex.caps.queue === 1
    readonly property bool supportsPlaylists: ex.bus !== "" && ex.caps.playlists === 1

    property var queue: []     // [{trackid,title,artist,length,art,current,played}]
    property var playlists: [] // [{path,name,icon,active}]

    // Absolute path to the busctl helper, exec'd directly (argv) so the D-Bus
    // bus name and playlist/track ids ride as opaque tokens instead of through
    // single-quoted shell fragments.
    readonly property string _script: Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/mpris-extra.sh"
    function _sh(mode, extra) {
        var argv = [ex._script, mode, String(ex.bus)];
        if (extra)
            argv.push(String(extra));
        return argv;
    }
    function _json(out, fallback) {
        try {
            return JSON.parse(out) || fallback;
        } catch (e) {
            return fallback;
        }
    }

    onBusChanged: {
        ex.queue = [];
        ex.playlists = [];
        ex.caps = {
            "queue": 0,
            "playlists": 0
        };
    }

    property CommandPoll capsPoll: CommandPoll {
        interval: 2000
        running: ex.bus !== "" && ex.popupOpen
        command: ex._sh("caps")
        parse: function (out) {
            return ex._json(out, {
                "queue": 0,
                "playlists": 0
            });
        }
        onUpdated: ex.caps = this.value
    }
    property CommandPoll queuePoll: CommandPoll {
        interval: 2000
        running: ex.bus !== "" && ex.queueWants
        command: ex._sh("queue")
        parse: function (out) {
            return ex._json(out, []);
        }
        onUpdated: ex.queue = this.value
    }
    property CommandPoll playlistsPoll: CommandPoll {
        interval: 5000
        running: ex.bus !== "" && ex.playlistsWants
        command: ex._sh("playlists")
        parse: function (out) {
            return ex._json(out, []);
        }
        onUpdated: ex.playlists = this.value
    }

    // Actions: optimistic local update for instant feedback, then fire + re-fetch.
    function goTo(trackid) {
        if (ex.bus === "" || !trackid)
            return;
        // Re-tag: the jumped-to track becomes current, everything before it in
        // context order is now "played" (greyed), everything after upcoming.
        var j = ex.queue.findIndex(function (t) {
            return t.trackid === trackid;
        });
        ex.queue = ex.queue.map(function (t, i) {
            return Object.assign({}, t, {
                "current": j >= 0 ? i === j : t.trackid === trackid,
                "played": j >= 0 ? i < j : t.played
            });
        });
        Quickshell.execDetached(ex._sh("goto", trackid));
        ex.queuePoll.poll();
    }
    function remove(trackid) {
        if (ex.bus === "" || !trackid)
            return;
        ex.queue = ex.queue.filter(function (t) {
            return t.trackid !== trackid;
        });
        Quickshell.execDetached(ex._sh("remove", trackid));
        ex.queuePoll.poll();
    }
    function activate(path) {
        if (ex.bus === "" || !path)
            return;
        ex.playlists = ex.playlists.map(function (p) {
            return Object.assign({}, p, {
                "active": p.path === path
            });
        });
        Quickshell.execDetached(ex._sh("activate", path));
    }
}
