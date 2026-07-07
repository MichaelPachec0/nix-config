import QtQuick
import Quickshell.Io
import "influx.js" as Influx

// AMD SMU metrics via a root-written InfluxDB line-protocol snapshot at
// /run/ryzen-monitor/latest.influx (written by ryzen_monitor_ng). Read with a
// FileView (Quickshell's native file idiom) reloaded on a timer; available drops
// to false when the file is absent (the service's RuntimeDirectory is removed
// when it stops), letting the caller fall back to lm_sensors. Hover-gated via
// `active`. Instantiated + passed by reference like the other Lib providers.
QtObject {
    id: root
    property bool active: false
    property bool available: false
    // Temperatures in whole degrees C (0 when absent).
    property real cpu: 0
    property real peak: 0
    property real soc: 0
    property real gfx: 0
    // Power/current actuals and their limits.
    property real ppt: 0
    property real pptLimit: 0
    property real stapm: 0
    property real stapmLimit: 0
    property real tdc: 0
    property real tdcLimit: 0
    property real edc: 0
    property real edcLimit: 0
    property real gfxBusy: 0
    property real fclk: 0
    property real mclk: 0
    // Per-core effective clock (MHz), indexed by core index; [] when absent.
    property var perCoreFreq: []

    // Map a parsed influx frame onto the exposed properties.
    function _apply(m) {
        function has(k) { return typeof m[k] === "number" && !isNaN(m[k]); }
        function num(k) { return has(k) ? m[k] : 0; }
        // CPU temp: prefer cpu_thm (Tdie), fall back to per-core max.
        var cpuT = has("cpu_thm") ? m.cpu_thm
                 : (has("cores_maxtemperature") ? m.cores_maxtemperature : 0);
        root.cpu = Math.round(cpuT);
        // Peak: hottest fused die reading (matches zenpower Tdie/Tctl), shown
        // alongside the smoother cpu_thm.
        root.peak = Math.round(num("package_peaktemperature"));
        // SoC temp: Renoir/APUs report soc_thmsoc (THM_VALUE_SOC); desktops may
        // report soc_temperature (SOC_TEMP). Prefer whichever exists.
        var socT = has("soc_thmsoc") ? m.soc_thmsoc
                 : (has("soc_temperature") ? m.soc_temperature : 0);
        root.soc = Math.round(socT);
        root.gfx = Math.round(num("gfx_temperature"));
        root.ppt = num("cpu_ppt");
        root.pptLimit = num("cpu_pptlimit");
        root.stapm = num("cpu_stapm");
        root.stapmLimit = num("cpu_stapmlimit");
        root.tdc = num("cpu_tdc");
        root.tdcLimit = num("cpu_tdclimit");
        root.edc = num("cpu_edc");
        root.edcLimit = num("cpu_edclimit");
        root.gfxBusy = num("gfx_busy");
        root.fclk = num("cpu_fabricclock");
        root.mclk = num("cpu_memoryclock");
        // Available only when a real temperature field parsed.
        root.available = has("cpu_thm") || has("cores_maxtemperature") || has("gfx_temperature");
    }

    // The snapshot is atomically replaced (mv) every ~2 s, so a timer-driven
    // reload() is more reliable than inode-based change watching.
    property FileView file: FileView {
        path: root.active ? "/run/ryzen-monitor/latest.influx" : ""
        onLoaded: {
            var txt = file.text();
            root._apply(Influx.parseFrame(txt));
            var pc = Influx.parsePerCore(txt);
            var arr = [];
            for (var k in pc) {
                if (typeof pc[k].core_frequency === "number")
                    arr[Number(k)] = pc[k].core_frequency;
            }
            root.perCoreFreq = arr;
        }
        onLoadFailed: {
            root.available = false;
            root.perCoreFreq = [];
        }
    }

    property Timer poll: Timer {
        interval: 2000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.file.reload()
    }
}
