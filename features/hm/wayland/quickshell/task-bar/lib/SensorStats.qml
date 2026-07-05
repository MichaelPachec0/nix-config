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
        command: ["bash", "-lc", "sensors -j 2>/dev/null"]
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
            // Many chips mirror the same physical temperature (the CPU reports via
            // thinkpad / acpitz / zenpower Tdie / Tctl, a few degrees apart);
            // collapse readings within 3 C of one already kept, first label wins.
            var kept = [];
            for (var i = 0; i < out.length; i++) {
                var dup = false;
                for (var k = 0; k < kept.length; k++) {
                    if (Math.abs(out[i].temp - kept[k].temp) <= 3) {
                        dup = true;
                        break;
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
