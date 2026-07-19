import QtQuick

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

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["bash", "-c",
            "echo @D; df -B1024 --output=target,used,size,pcent -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay 2>/dev/null | tail -n +2; " +
            "echo @IO; awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]|vd[a-z]|mmcblk[0-9]+)$/ {r+=$6; w+=$10} END {print r, w}' /proc/diskstats; " +
            "echo @NOW; date +%s%3N"]
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
                    var p = ln.trim().split(/\s+/);
                    var pct = Number(String(p[3]).replace("%", "")) || 0;
                    out.mounts.push({ target: p[0], usedKB: Number(p[1]), sizeKB: Number(p[2]), pct: pct });
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
