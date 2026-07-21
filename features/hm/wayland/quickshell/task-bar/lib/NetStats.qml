import QtQuick
import Quickshell

// Per-interface rx/tx rates for every active (carrier=1, non-lo) interface,
// from /sys/class/net statistics deltas. carrier=1 (not operstate=up) so bridges
// / zerotier / tun report as active. Hover-gated via `active`. Instantiated +
// passed by reference like the other Lib services.
QtObject {
    id: root
    property bool active: false
    property bool available: false
    property var ifaces: []      // [{ name, rx, tx }] bytes/s
    property var _prev: null     // { t, map:{name:{rx,tx}} }

    // Drop the last sample when the popup closes (poll stops) so the first rate
    // after reopen is a fresh 0, not a rate smeared over the whole closed gap.
    onActiveChanged: if (!root.active) root._prev = null;

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.active
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/net-io.sh"]
        parse: function (o) {
            var out = { map: {}, order: [], now: 0 };
            String(o).split("\n").forEach(function (ln) {
                if (!ln.trim())
                    return;
                var p = ln.trim().split(/\s+/);
                if (p[0] === "@NOW") {
                    out.now = Number(p[1]) || 0;
                    return;
                }
                if (p.length >= 3) {
                    out.map[p[0]] = { rx: Number(p[1]) || 0, tx: Number(p[2]) || 0 };
                    out.order.push(p[0]);
                }
            });
            return out;
        }
        onUpdated: {
            var v = value;
            var list = [];
            if (root._prev && v.now > root._prev.t) {
                var dt = (v.now - root._prev.t) / 1000;
                v.order.forEach(function (n) {
                    var cur = v.map[n], pr = root._prev.map[n];
                    var rx = pr ? Math.max(0, (cur.rx - pr.rx) / dt) : 0;
                    var tx = pr ? Math.max(0, (cur.tx - pr.tx) / dt) : 0;
                    list.push({ name: n, rx: rx, tx: tx });
                });
            } else {
                v.order.forEach(function (n) {
                    list.push({ name: n, rx: 0, tx: 0 });
                });
            }
            root.ifaces = list;
            root.available = list.length > 0;
            root._prev = { t: v.now, map: v.map };
        }
    }
}
