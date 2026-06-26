import QtQuick

// Shared CPU%/RAM% poller, read by both the bar (Taskbar) and the hub Header.
// Instantiated once per monitor in shell.qml so /proc is polled in one place.
// CPU% = busy fraction from successive /proc/stat samples; RAM% = used/total.
QtObject {
    id: root

    property bool active: true
    property real cpuPct: 0
    property real ramPct: 0
    property var _prevCpu: null

    property CommandPoll cpuPoll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["bash", "-lc", "head -1 /proc/stat"]
        parse: function (o) {
            var n = String(o).trim().split(/\s+/).slice(1).map(Number);
            var idle = (n[3] || 0) + (n[4] || 0);
            var total = n.reduce(function (a, b) {
                return a + (b || 0);
            }, 0);
            return {
                total: total,
                idle: idle
            };
        }
        onUpdated: {
            var cur = value;
            if (root._prevCpu) {
                var dt = cur.total - root._prevCpu.total;
                var di = cur.idle - root._prevCpu.idle;
                if (dt > 0)
                    root.cpuPct = Math.max(0, Math.min(100, Math.round(100 * (1 - di / dt))));
            }
            root._prevCpu = cur;
        }
    }

    property CommandPoll ramPoll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["bash", "-lc", "cat /proc/meminfo"]
        parse: function (o) {
            var t = String(o).match(/MemTotal:\s+(\d+)/);
            var a = String(o).match(/MemAvailable:\s+(\d+)/);
            if (t && a) {
                var total = Number(t[1]);
                var avail = Number(a[1]);
                return total > 0 ? Math.round(100 * (total - avail) / total) : 0;
            }
            return 0;
        }
        onUpdated: root.ramPct = value
    }
}
