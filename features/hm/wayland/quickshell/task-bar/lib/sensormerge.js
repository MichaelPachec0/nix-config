// Sensor classification and SMU-vs-lm_sensors merge logic. Plain top-level JS
// so it is both a QML JS resource (import "../lib/sensormerge.js" as SensorMerge)
// and readable by the Deno test via indirect eval. Do NOT add `.pragma library`.

// Classify a sensor chip label into "cpu"|"gpu"|"soc"|"other".
// Order matters: gpu and soc are checked before the broad cpu pattern.
function classifyChip(label) {
    if (/amdgpu|radeon|\bgpu\b|edge|junction/i.test(label))
        return "gpu";
    if (/\bsoc\b/i.test(label))
        return "soc";
    if (/zenpower|k10temp|tctl|tdie|\bcpu\b|core|package|thinkpad|acpitz/i.test(label))
        return "cpu";
    return "other";
}

// Merge lm_sensors entries with SMU temps. When SMU is available it replaces
// all lm entries of the same kind (cpu/gpu/soc); unmatched lm entries are kept.
// Returns lmList unchanged when smu is absent or unavailable.
function mergeSensors(lmList, smu) {
    if (!smu || !smu.available)
        return lmList;

    // Build the SMU entries and record which kinds were supplied.
    var smuEntries = [];
    var supplied = {};
    if (smu.cpu > 0) {
        smuEntries.push({ label: "CPU", temp: smu.cpu });
        supplied["cpu"] = true;
    }
    // Peak die temp (package_peaktemperature ~= Tdie/Tctl): the hottest fused
    // reading, shown next to the smoother cpu_thm. Also an AMD cpu-kind reading,
    // so it suppresses the lm_sensors CPU entries too.
    if (smu.peak > 0) {
        smuEntries.push({ label: "CPU Pk", temp: smu.peak });
        supplied["cpu"] = true;
    }
    if (smu.soc > 0) {
        smuEntries.push({ label: "SoC", temp: smu.soc });
        supplied["soc"] = true;
    }
    if (smu.gfx > 0) {
        smuEntries.push({ label: "GFX", temp: smu.gfx });
        supplied["gpu"] = true;
    }

    // Keep lm entries whose kind was not covered by SMU.
    var kept = [];
    for (var i = 0; i < lmList.length; i++) {
        var kind = classifyChip(lmList[i].label);
        if (!supplied[kind])
            kept.push(lmList[i]);
    }

    return smuEntries.concat(kept);
}
