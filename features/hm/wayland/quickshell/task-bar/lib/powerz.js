// Parse lib/powerz.sh stdout into a reading object for PowerZStats.qml.
// Plain top-level JS (NO `.pragma library`) so it loads both as a QML JS
// resource (import "powerz.js" as PowerZ) and via the Deno indirect-eval test,
// exactly like sensormerge.js.
//
// Input is key/value lines. `state:` is always present (active|busy|absent).
// vbus/ibus/cc1/cc2 carry RAW sysfs integers (milli-units) and only appear when
// active; we convert to volts/amps here so QML and the tests share one
// definition. power (W) = vbus(V) * ibus(A). Non-active states zero the readings.
function parsePowerz(text) {
    var m = {};
    String(text || "").split("\n").forEach(function (line) {
        var i = line.indexOf(":");
        if (i < 0)
            return;
        var k = line.slice(0, i).trim().toLowerCase();
        var v = line.slice(i + 1).trim();
        if (k)
            m[k] = v;
    });

    var state = (m["state"] === "active" || m["state"] === "busy") ? m["state"] : "absent";
    var out = {
        state: state,
        available: state === "active",
        vbus: 0,
        ibus: 0,
        cc1: 0,
        cc2: 0,
        power: 0
    };
    if (state !== "active")
        return out;

    out.vbus = (Number(m["vbus"]) || 0) / 1000; // mV -> V
    out.ibus = (Number(m["ibus"]) || 0) / 1000; // mA -> A
    out.cc1 = (Number(m["cc1"]) || 0) / 1000;   // mV -> V
    out.cc2 = (Number(m["cc2"]) || 0) / 1000;   // mV -> V
    out.power = out.vbus * out.ibus;            // W
    return out;
}
