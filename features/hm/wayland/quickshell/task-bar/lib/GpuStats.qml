import QtQuick

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
    property var gpuHist: []

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.active
        command: ["bash", "-lc",
            "c=''; for d in /sys/class/drm/card*/device/gpu_busy_percent; do [ -e \"$d\" ] && c=\"${d%/gpu_busy_percent}\" && break; done; " +
            "if [ -n \"$c\" ]; then " +
            "  echo util=$(cat \"$c/gpu_busy_percent\" 2>/dev/null); " +
            "  echo vramUsed=$(cat \"$c/mem_info_vram_used\" 2>/dev/null); " +
            "  echo vramTotal=$(cat \"$c/mem_info_vram_total\" 2>/dev/null); " +
            "  echo temp=$(cat \"$c\"/hwmon/hwmon*/temp1_input 2>/dev/null | head -1); " +
            "elif command -v nvidia-smi >/dev/null; then " +
            "  read u mu mt t < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | head -1 | tr -d ','); " +
            "  echo util=$u; echo vramUsed=$((mu*1048576)); echo vramTotal=$((mt*1048576)); echo temp=$((t*1000)); " +
            "fi"]
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
            root.available = (v.util !== null && !isNaN(v.util));
            if (!root.available)
                return;
            root.util = v.util;
            root.vramUsed = v.vramUsed;
            root.vramTotal = v.vramTotal;
            root.temp = v.temp;
            var h = root.gpuHist.slice();
            h.push(root.util);
            if (h.length > 30)
                h.shift();
            root.gpuHist = h;
        }
    }
}
