import QtQuick
import Quickshell

// Filesystem usage (df, real mounts only) + aggregate disk I/O rate from
// /proc/diskstats deltas (sectors*512). Hover-gated via `active`. Instantiated +
// passed by reference like the other Lib services.
QtObject {
    id: root
    property bool active: false
    property bool available: false
    property var mounts: []       // [{ target, usedKB, sizeKB, pct }]
    property real readRate: 0     // bytes/s
    property real writeRate: 0    // bytes/s
    property var _prev: null      // { t, rd, wr }

    // Drop the last sample when the popup closes (poll stops) so the first rate
    // after reopen is a fresh 0, not a rate smeared over the whole closed gap.
    onActiveChanged: if (!root.active) root._prev = null;

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.active
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/disk-stats.sh"]
        parse: function (o) {
            var out = { mounts: [], rd: 0, wr: 0, now: 0 };
            var tag = "";
            String(o).split("\n").forEach(function (ln) {
                if (ln.charAt(0) === "@") {
                    tag = ln.substring(1).trim();
                    return;
                }
                if (!ln.trim())
                    return;
                if (tag === "D") {
                    // Fields are: target used size pcent. The target is first and
                    // may contain spaces (e.g. "/mnt/My Drive"), so take the
                    // numeric trio from the RIGHT and join everything before it as
                    // the target -- a positional p[0..3] split mis-parses spaces.
                    var p = ln.trim().split(/\s+/);
                    if (p.length < 4)
                        return;
                    var pct = Number(String(p[p.length - 1]).replace("%", "")) || 0;
                    var sizeKB = Number(p[p.length - 2]);
                    var usedKB = Number(p[p.length - 3]);
                    var target = p.slice(0, p.length - 3).join(" ");
                    out.mounts.push({ target: target, usedKB: usedKB, sizeKB: sizeKB, pct: pct });
                } else if (tag === "IO") {
                    var q = ln.trim().split(/\s+/);
                    out.rd = Number(q[0]) || 0;
                    out.wr = Number(q[1]) || 0;
                } else if (tag === "NOW") {
                    out.now = Number(ln.trim()) || 0;
                }
            });
            return out;
        }
        onUpdated: {
            var v = value;
            root.mounts = v.mounts;
            root.available = v.mounts.length > 0;
            if (root._prev && v.now > root._prev.t) {
                var dt = (v.now - root._prev.t) / 1000;
                root.readRate = Math.max(0, (v.rd - root._prev.rd) * 512 / dt);
                root.writeRate = Math.max(0, (v.wr - root._prev.wr) * 512 / dt);
            }
            root._prev = { t: v.now, rd: v.rd, wr: v.wr };
        }
    }
}
