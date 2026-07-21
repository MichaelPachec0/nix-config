import QtQuick

// Temperature sensors via `sensors -j` (lm_sensors JSON). Generic: walks every
// chip, keeps each populated tempN_input (drops 0/unpopulated), and builds a
// short label ("chip" for generic tempN names, else "chip sensor"). available =
// at least one temp found (hidden otherwise). Hover-gated via `active`.
// Instantiated + passed by reference like the other Lib providers.
QtObject {
    id: root
    property bool active: false
    property bool available: false
    property var sensors: []   // [{ label, temp }] temp in whole degrees C

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["sensors", "-j"]
        parse: function (o) {
            var out = [];
            try {
                var j = JSON.parse(o);
                for (var chip in j) {
                    var chipShort = String(chip).replace(/[-_](pci|isa|virtual|acpi)[-_].*$/i, "").replace(/_\d+$/, "");
                    var obj = j[chip];
                    for (var sname in obj) {
                        if (sname === "Adapter")
                            continue;
                        var s = obj[sname];
                        if (!s || typeof s !== "object")
                            continue;
                        for (var key in s) {
                            if (!/^temp\d+_input$/.test(key))
                                continue;
                            var t = Number(s[key]);
                            if (isNaN(t) || t <= 0)
                                continue;
                            var label = /^temp\d+$/.test(sname) ? chipShort : (chipShort + " " + sname);
                            out.push({ label: label, temp: Math.round(t) });
                        }
                    }
                }
            } catch (e) {
                out = [];
            }
            // The CPU reports its temperature through several chips a few degrees
            // apart (k10temp / zenpower Tctl / Tdie, coretemp, acpitz, thinkpad);
            // collapse those mirrors to one, first label wins. Scope the dedup to
            // CPU-family labels so an unrelated sensor that merely sits within 3 C
            // (e.g. an NVMe drive near the CPU temp) is never dropped.
            var isCpu = function (lbl) {
                return /k10temp|zenpower|coretemp|acpitz|thinkpad|tctl|tdie|package|\bcpu\b/i.test(lbl);
            };
            var kept = [];
            for (var i = 0; i < out.length; i++) {
                var dup = false;
                if (isCpu(out[i].label)) {
                    for (var k = 0; k < kept.length; k++) {
                        if (isCpu(kept[k].label) && Math.abs(out[i].temp - kept[k].temp) <= 3) {
                            dup = true;
                            break;
                        }
                    }
                }
                if (!dup)
                    kept.push(out[i]);
            }
            return kept;
        }
        onUpdated: {
            root.sensors = value;
            root.available = value.length > 0;
        }
    }
}
