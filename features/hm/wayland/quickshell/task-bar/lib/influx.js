// Parser for ryzen_monitor_ng InfluxDB line-protocol frames. Plain top-level JS
// so it is both a QML JS resource (import "../lib/influx.js" as Influx) and
// readable by the Deno test via indirect eval. Do NOT add `.pragma library`.

// Parse one InfluxDB line-protocol frame (possibly multi-line) into a flat
// { key: number } object. String/boolean fields are skipped. Returns {} on
// empty or unparseable input.
function parseFrame(text) {
    var result = {};
    if (!text)
        return result;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line)
            continue;
        // Everything up to the first space is measurement+tags; discard it.
        var sp = line.indexOf(" ");
        if (sp < 0)
            continue;
        var fields = line.slice(sp + 1);
        // Line protocol is "<measurement,tags> <fields> [timestamp]". Field
        // values carry no unescaped spaces, so a trailing space-separated integer
        // is the timestamp -- drop it, else the last field absorbs it -> NaN.
        var ts = fields.lastIndexOf(" ");
        if (ts >= 0 && /^\d+$/.test(fields.slice(ts + 1)))
            fields = fields.slice(0, ts);
        var pairs = fields.split(",");
        for (var j = 0; j < pairs.length; j++) {
            var eq = pairs[j].indexOf("=");
            if (eq < 0)
                continue;
            var key = pairs[j].slice(0, eq);
            var raw = pairs[j].slice(eq + 1);
            // Strip a single trailing Influx integer marker.
            if (raw.charAt(raw.length - 1) === "i")
                raw = raw.slice(0, raw.length - 1);
            var num = Number(raw);
            if (isNaN(num))
                continue;
            result[key] = num;
        }
    }
    return result;
}

// Parse per-core lines (tagged name=CoreN) into { <coreIndex>: { key: number } }.
// The aggregate "name=Cores" line has no digit after "Core" so it is excluded.
// Field parsing mirrors parseFrame (numeric only, trailing "i" stripped).
function parsePerCore(text) {
    var result = {};
    if (!text)
        return result;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line)
            continue;
        var sp = line.indexOf(" ");
        if (sp < 0)
            continue;
        var m = line.slice(0, sp).match(/name=Core(\d+)/);
        if (!m)
            continue;
        var idx = Number(m[1]);
        var obj = {};
        var fields = line.slice(sp + 1);
        var ts = fields.lastIndexOf(" ");
        if (ts >= 0 && /^\d+$/.test(fields.slice(ts + 1)))
            fields = fields.slice(0, ts);
        var pairs = fields.split(",");
        for (var j = 0; j < pairs.length; j++) {
            var eq = pairs[j].indexOf("=");
            if (eq < 0)
                continue;
            var key = pairs[j].slice(0, eq);
            var raw = pairs[j].slice(eq + 1);
            if (raw.charAt(raw.length - 1) === "i")
                raw = raw.slice(0, raw.length - 1);
            var num = Number(raw);
            if (isNaN(num))
                continue;
            obj[key] = num;
        }
        result[idx] = obj;
    }
    return result;
}
