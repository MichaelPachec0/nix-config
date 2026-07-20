import QtQuick
import Quickshell

// Modular GPU stats. One poll auto-detects the backend and prints normalized
// K=V; AMD via sysfs, NVIDIA via nvidia-smi. available=false (section hidden)
// when neither is present. Hover-gated via `active`. Instantiated + passed by
// reference like the other Lib services.
QtObject {
    id: root
    property bool active: false
    property bool available: false
    property real util: 0
    property real vramUsed: 0
    property real vramTotal: 0
    property real temp: 0
    property var gpuHist: []    // utilization % history
    property var vramHist: []   // VRAM used % history

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.active
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/gpu-stats.sh"]
        parse: function (o) {
            var r = { util: null, vramUsed: 0, vramTotal: 0, temp: 0 };
            String(o).split("\n").forEach(function (ln) {
                var m = ln.match(/^(\w+)=(.*)$/);
                if (!m)
                    return;
                if (m[1] === "util")
                    r.util = m[2] === "" ? null : Number(m[2]);
                else if (m[1] === "vramUsed")
                    r.vramUsed = Number(m[2]) || 0;
                else if (m[1] === "vramTotal")
                    r.vramTotal = Number(m[2]) || 0;
                else if (m[1] === "temp")
                    r.temp = (Number(m[2]) || 0) / 1000;
            });
            return r;
        }
        onUpdated: {
            var v = value;
            // Latch availability: a transient empty sysfs read (util null) must
            // NOT drop the GPU section for a tick (flicker). Once a good read is
            // seen, keep available true and just skip the bad tick. Machines with
            // no GPU never produce util, so available stays false (section hidden).
            if (v.util === null || isNaN(v.util))
                return;
            root.available = true;
            root.util = v.util;
            root.vramUsed = v.vramUsed;
            root.vramTotal = v.vramTotal;
            root.temp = v.temp;
            var h = root.gpuHist.slice();
            h.push(root.util);
            if (h.length > 30)
                h.shift();
            root.gpuHist = h;
            var vp = root.vramTotal > 0 ? (root.vramUsed / root.vramTotal * 100) : 0;
            var hv = root.vramHist.slice();
            hv.push(vp);
            if (hv.length > 30)
                hv.shift();
            root.vramHist = hv;
        }
    }
}
