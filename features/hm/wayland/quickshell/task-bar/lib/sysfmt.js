// Pure helpers for the system stats popup. Plain top-level JS so it is both a
// QML JS resource (import "../lib/sysfmt.js" as SysFmt) and readable by the Deno
// test via indirect eval. Do NOT add `.pragma library`.

// Severity band thresholds per metric ([fair, poor] cutoffs). Module-level so the
// table is built once, not rebuilt on every severity() call.
var SEVERITY_BANDS = {
    cpu: [70, 88], mem: [70, 88], swap: [10, 50], temp: [70, 85], psi: [5, 20]
};

// Severity band for a metric value -> "good"|"fair"|"poor" (spec coloring table).
function severity(metric, value) {
    if (value === null || value === undefined || isNaN(value))
        return "good";
    var b = SEVERITY_BANDS[metric];
    if (!b)
        return "good";
    if (value < b[0])
        return "good";
    if (value < b[1])
        return "fair";
    return "poor";
}

// Map a severity band ("good"|"fair"|"poor") to a theme accent colour. Shared by
// every Sys*Section (and the dock) so the band->colour mapping lives in one
// place; pass the section's `theme` explicitly.
function sevColor(theme, sev) {
    return sev === "good" ? theme.accentGreen
         : sev === "fair" ? theme.accentYellow : theme.accentRed;
}

// Kilobytes (as reported by /proc/meminfo and ps rss) -> human string.
function fmtKB(kb) {
    var v = Number(kb) || 0;
    var u = ["K", "M", "G", "T"];
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
        v /= 1024;
        i++;
    }
    return (i >= 2 ? v.toFixed(1) : String(Math.round(v))) + u[i];
}

// Bytes/second -> human string (binary units).
function fmtRate(bps) {
    var v = Number(bps) || 0;
    var u = ["B", "K", "M", "G"];
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
        v /= 1024;
        i++;
    }
    return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i] + "/s";
}

// Group CPU topology lines "<logical> <core_id> <l3_shared_list>" into
// [ { ccx, cores: [ { coreId, threads:[logical...] } ] } ], ordered by CCX
// first-appearance, then core_id, then thread. Cores sharing an L3 list are one
// CCX; an empty L3 column collapses everything into a single CCX.
function parseTopology(text) {
    if (!text)
        return [];
    var lines = String(text).split("\n");
    var order = [];      // l3 key in first-appearance order
    var map = {};        // l3 key -> { ccx, coreMap, coreOrder }
    for (var i = 0; i < lines.length; i++) {
        var ln = lines[i].trim();
        if (!ln)
            continue;
        var p = ln.split(/\s+/);
        if (p.length < 2)
            continue;
        var logical = Number(p[0]);
        var coreId = Number(p[1]);
        if (isNaN(logical) || isNaN(coreId))
            continue;
        var key = (p.length >= 3 && p[2]) ? p[2] : "__single__";
        if (!(key in map)) {
            map[key] = { ccx: order.length, coreMap: {}, coreOrder: [] };
            order.push(key);
        }
        var grp = map[key];
        if (!(coreId in grp.coreMap)) {
            grp.coreMap[coreId] = [];
            grp.coreOrder.push(coreId);
        }
        grp.coreMap[coreId].push(logical);
    }
    var out = [];
    for (var c = 0; c < order.length; c++) {
        var g = map[order[c]];
        g.coreOrder.sort(function (a, b) { return a - b; });
        var cores = [];
        for (var k = 0; k < g.coreOrder.length; k++) {
            var cid = g.coreOrder[k];
            cores.push({
                coreId: cid,
                threads: g.coreMap[cid].slice().sort(function (a, b) { return a - b; })
            });
        }
        out.push({ ccx: g.ccx, cores: cores });
    }
    return out;
}
