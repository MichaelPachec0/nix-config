import QtQuick
import "sysfmt.js" as SysFmt

// Shared CPU%/RAM% poller, read by both the bar (Taskbar) and the hub Header.
// Instantiated once per monitor in shell.qml so /proc is polled in one place.
// CPU% = busy fraction from successive /proc/stat samples; RAM% = used/total.
QtObject {
    id: root

    property bool active: true
    property real cpuPct: 0
    property real ramPct: 0
    property var cpuHist: []
    property var ramHist: []
    readonly property int _histMax: 30
    function _pushHist(arr, v) {
        var h = arr.slice();
        h.push(v);
        if (h.length > root._histMax)
            h.shift();
        return h;
    }
    property var _prevCpu: null

    property CommandPoll cpuPoll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["head", "-1", "/proc/stat"]
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
            root.cpuHist = root._pushHist(root.cpuHist, root.cpuPct);
        }
    }

    property CommandPoll ramPoll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["cat", "/proc/meminfo"]
        parse: function (o) {
            // Return a fresh object every tick so CommandPoll's change-detection
            // always fires updated() -- otherwise a steady ram% would suppress it
            // and ramHist (the sparkline) would never advance.
            var t = String(o).match(/MemTotal:\s+(\d+)/);
            var a = String(o).match(/MemAvailable:\s+(\d+)/);
            var pct = 0;
            if (t && a) {
                var total = Number(t[1]);
                var avail = Number(a[1]);
                pct = total > 0 ? Math.round(100 * (total - avail) / total) : 0;
            }
            return { pct: pct };
        }
        onUpdated: {
            root.ramPct = value.pct;
            root.ramHist = root._pushHist(root.ramHist, root.ramPct);
        }
    }

    // --- Detailed stats for the system popup; polled only while it is open. ---
    property bool wantDetail: false
    property var perCore: []
    property var cpuTopology: []
    property var perThreadFreq: []
    property var load: [0, 0, 0]
    property real cpuTemp: 0
    property real uptime: 0
    property var mem: ({})
    property var swap: ({})
    property var psi: ({ cpu: 0, mem: 0 })
    property var topMem: []
    property var topCpu: []
    property var _prevCore: null

    // Per-thread busy fraction (delta over the previous sample) + per-thread
    // cpufreq (point-in-time). The @F tag splits /proc/stat util lines from the
    // scaling_cur_freq lines; the freq loop is numeric-ordered to match logical
    // CPU indices. perThreadFreq is the fallback clock when SMU is unavailable.
    property CommandPoll corePoll: CommandPoll {
        interval: 2000
        running: root.active && root.wantDetail
        command: ["bash", "-c",
            "grep '^cpu[0-9]' /proc/stat; echo @F; " +
            "for c in /sys/devices/system/cpu/cpu[0-9]*; do n=${c##*/cpu}; " +
            "printf '%s %s\\n' \"$n\" \"$(cat \"$c/cpufreq/scaling_cur_freq\" 2>/dev/null)\"; " +
            "done | sort -n"]
        parse: function (o) {
            var lines = String(o).split("\n");
            var cpus = [];
            var freq = [];
            var inFreq = false;
            for (var i = 0; i < lines.length; i++) {
                var ln = lines[i];
                if (ln.charAt(0) === "@") { inFreq = true; continue; }
                if (!ln.trim()) continue;
                if (!inFreq) {
                    var n = ln.trim().split(/\s+/).slice(1).map(Number);
                    var idle = (n[3] || 0) + (n[4] || 0);
                    var total = n.reduce(function (a, b) { return a + (b || 0); }, 0);
                    cpus.push({ total: total, idle: idle });
                } else {
                    var p = ln.trim().split(/\s+/);
                    var li = Number(p[0]);
                    var khz = Number(p[1]);
                    if (!isNaN(li))
                        freq[li] = isNaN(khz) ? 0 : Math.round(khz / 1000);
                }
            }
            return { cpus: cpus, freq: freq };
        }
        onUpdated: {
            var cur = value;
            if (root._prevCore && root._prevCore.length === cur.cpus.length) {
                var out = [];
                for (var i = 0; i < cur.cpus.length; i++) {
                    var dt = cur.cpus[i].total - root._prevCore[i].total;
                    var di = cur.cpus[i].idle - root._prevCore[i].idle;
                    out.push(dt > 0 ? Math.max(0, Math.min(100, Math.round(100 * (1 - di / dt)))) : 0);
                }
                root.perCore = out;
            }
            root._prevCore = cur.cpus;
            root.perThreadFreq = cur.freq;
        }
    }

    // CPU topology (static): logical -> core (core_id) -> CCX (shared L3).
    // Self-disabling: runs once (CommandPoll fires on start) then stops when
    // cpuTopology is populated. Numeric loop avoids the lexical cpu* glob order.
    property CommandPoll topoPoll: CommandPoll {
        interval: 60000
        running: root.active && root.wantDetail && root.cpuTopology.length === 0
        command: ["bash", "-c",
            "for c in /sys/devices/system/cpu/cpu[0-9]*; do n=${c##*/cpu}; " +
            "printf '%s %s %s\\n' \"$n\" \"$(cat \"$c/topology/core_id\" 2>/dev/null)\" " +
            "\"$(cat \"$c/cache/index3/shared_cpu_list\" 2>/dev/null)\"; done | sort -n"]
        parse: function (o) { return SysFmt.parseTopology(String(o)); }
        onUpdated: root.cpuTopology = value
    }

    // Everything else in one bash call (all point-in-time -- no delta needed).
    property CommandPoll detailPoll: CommandPoll {
        interval: 2000
        running: root.active && root.wantDetail
        command: ["bash", "-c",
            "echo @L; cat /proc/loadavg; " +
            "echo @M; cat /proc/meminfo; " +
            "echo @P; head -1 /proc/pressure/cpu; head -1 /proc/pressure/memory; " +
            "echo @U; cat /proc/uptime; " +
            "echo @T; for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name 2>/dev/null)\" = zenpower ] && cat $h/temp1_input 2>/dev/null && break; done; " +
            "echo @TM; ps -eo pid,rss,pmem,comm --sort=-rss | head -6; " +
            "echo @TC; ps -eo pid,pcpu,comm --sort=-pcpu | head -6"]
        parse: function (o) {
            var out = { load: [0, 0, 0], mem: {}, swap: {}, psi: { cpu: 0, mem: 0 },
                        uptime: 0, cpuTemp: 0, topMem: [], topCpu: [] };
            var mi = {};
            var tag = "";
            var psiIdx = 0;
            var lines = String(o).split("\n");
            for (var i = 0; i < lines.length; i++) {
                var ln = lines[i];
                if (ln.charAt(0) === "@") {
                    tag = ln.substring(1).trim();
                    continue;
                }
                if (!ln.trim())
                    continue;
                if (tag === "L") {
                    var p = ln.trim().split(/\s+/);
                    out.load = [Number(p[0]), Number(p[1]), Number(p[2])];
                } else if (tag === "M") {
                    var mm = ln.match(/^(\w+):\s+(\d+)/);
                    if (mm)
                        mi[mm[1]] = Number(mm[2]);
                } else if (tag === "P") {
                    var av = ln.match(/some avg10=([\d.]+)/);
                    if (av) {
                        if (psiIdx === 0)
                            out.psi.cpu = Number(av[1]);
                        else
                            out.psi.mem = Number(av[1]);
                        psiIdx++;
                    }
                } else if (tag === "U") {
                    out.uptime = Number(ln.trim().split(/\s+/)[0]);
                } else if (tag === "T") {
                    out.cpuTemp = Math.round(Number(ln.trim()) / 1000);
                } else if (tag === "TM") {
                    if (/^\s*PID/i.test(ln))
                        continue;
                    var pm = ln.trim().split(/\s+/);
                    if (pm.length >= 4)
                        out.topMem.push({ pid: Number(pm[0]), rssKB: Number(pm[1]),
                                          pmem: Number(pm[2]), name: pm.slice(3).join(" ") });
                } else if (tag === "TC") {
                    if (/^\s*PID/i.test(ln))
                        continue;
                    var pc = ln.trim().split(/\s+/);
                    if (pc.length >= 3)
                        out.topCpu.push({ pid: Number(pc[0]), pcpu: Number(pc[1]),
                                          name: pc.slice(2).join(" ") });
                }
            }
            var total = mi.MemTotal || 0, free = mi.MemFree || 0;
            var cached = (mi.Buffers || 0) + (mi.Cached || 0) + (mi.SReclaimable || 0);
            var used = total - free - cached;
            out.mem = { totalKB: total, usedKB: used, cachedKB: cached, freeKB: free,
                        usedPct: total > 0 ? Math.round(100 * used / total) : 0 };
            var st = mi.SwapTotal || 0, sf = mi.SwapFree || 0;
            out.swap = { totalKB: st, usedKB: st - sf, pct: st > 0 ? Math.round(100 * (st - sf) / st) : 0 };
            out.topMem = out.topMem.slice(0, 5);
            out.topCpu = out.topCpu.slice(0, 5);
            return out;
        }
        onUpdated: {
            var v = value;
            root.load = v.load;
            root.mem = v.mem;
            root.swap = v.swap;
            root.psi = v.psi;
            root.cpuTemp = v.cpuTemp;
            root.uptime = v.uptime;
            root.topMem = v.topMem;
            root.topCpu = v.topCpu;
        }
    }
}
