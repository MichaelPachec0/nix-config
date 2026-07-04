pragma ComponentBehavior: Bound
import QtQml
import Quickshell
import Quickshell.Services.Pipewire

// Shared, reactive audio state for the bar widget, mixer dropdown and hover
// mini. Wraps the native Pipewire module: the default sink/source drive master
// volume/mute, and the node model is filtered into output devices, input
// devices and per-app output streams. Instantiated once at ShellRoot and passed
// to the bar as `audio:` (mirrors BluetoothService / the `bt:` wiring).
//
// Native reactivity note: bindings to `node.audio.volume`/`muted` are live
// WITHOUT a bump counter (PwNodeAudio is a QObject with NOTIFYs) -- but ONLY
// while the node is bound. The PwObjectTracker below keeps every displayed node
// bound so the mixer sliders never go stale. The lists themselves re-derive on
// add/remove via the nodes model's own `values` NOTIFY.
QtObject {
    id: svc

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var defaultSink: svc.sink
    readonly property var defaultSource: svc.source
    readonly property bool ready: Pipewire.ready && svc.sink !== null

    readonly property int volume: (svc.sink && svc.sink.audio) ? Math.round(svc.sink.audio.volume * 100) : 0
    readonly property bool muted: (svc.sink && svc.sink.audio) ? svc.sink.audio.muted : false

    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: svc.nodes.filter(function (n) {
        return n && n.audio && n.isSink && !n.isStream;
    })
    readonly property var sources: svc.nodes.filter(function (n) {
        return n && n.audio && !n.isSink && !n.isStream;
    })
    readonly property var streams: svc.nodes.filter(function (n) {
        return n && n.audio && n.isSink && n.isStream;
    })

    // Keep defaults + every listed node bound so audio props stay live.
    readonly property var tracked: {
        var out = [];
        if (svc.sink)
            out.push(svc.sink);
        if (svc.source)
            out.push(svc.source);
        return out.concat(svc.sinks).concat(svc.sources).concat(svc.streams);
    }
    property PwObjectTracker tracker: PwObjectTracker {
        objects: svc.tracked
    }

    // --- Master controls ---------------------------------------------------
    function setVolume(pct) {
        if (svc.sink && svc.sink.audio)
            svc.sink.audio.volume = Math.max(0, Math.min(100, pct)) / 100;
    }
    function stepVolume(delta) {
        svc.setVolume(svc.volume + delta);
    }
    function toggleMute() {
        if (svc.sink && svc.sink.audio)
            svc.sink.audio.muted = !svc.sink.audio.muted;
    }

    // --- Default device selection ------------------------------------------
    function setDefaultSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }
    function setDefaultSource(node) {
        if (node)
            Pipewire.preferredDefaultAudioSource = node;
    }

    // --- Per-app routing (only thing native can't do) ----------------------
    // Each stream's current selection: { "<streamId>": "auto" | "<sinkNodeName>" }.
    // The routing target is NOT exposed on the node, so it is sourced from the
    // target.object metadata via a poll (gated to while a mixer wants it), and
    // updated optimistically on our own actions so the highlighted chip flips
    // instantly.
    property bool routeWants: false
    property var targets: ({})

    property CommandPoll targetsPoll: CommandPoll {
        interval: 2000
        running: svc.routeWants && svc.ready
        command: ["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/audioctl.sh targets"]
        parse: function (out) {
            var m = {};
            String(out || "").trim().split("\n").forEach(function (line) {
                var i = line.indexOf("=");
                if (i > 0)
                    m[line.slice(0, i)] = line.slice(i + 1);
            });
            return m;
        }
        onUpdated: svc.targets = this.value
    }

    // The endpoint a stream is routed to: "auto" or a sink's node.name.
    function streamEndpoint(streamNode) {
        if (!streamNode)
            return "auto";
        var v = svc.targets[String(streamNode.id)];
        return v ? v : "auto";
    }
    function _setTarget(streamId, endpoint) {
        var t = {};
        for (var k in svc.targets)
            t[k] = svc.targets[k];
        t[String(streamId)] = endpoint;
        svc.targets = t;
    }

    // Pin a stream to a specific sink (sets target.object to its serial).
    function routeStream(streamNode, sinkNode) {
        if (!streamNode || !sinkNode)
            return;
        svc._setTarget(streamNode.id, String(sinkNode.name));
        Quickshell.execDetached(["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/audioctl.sh route " + streamNode.id + " '" + String(sinkNode.name) + "'"]);
    }
    // Clear a stream's target so it follows the global default sink (auto).
    function routeStreamAuto(streamNode) {
        if (!streamNode)
            return;
        svc._setTarget(streamNode.id, "auto");
        Quickshell.execDetached(["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/audioctl.sh auto " + streamNode.id]);
    }

    // --- Display helpers ----------------------------------------------------
    function deviceLabel(node) {
        if (!node)
            return "";
        return String(node.description || node.nickname || node.name || "");
    }
    function appName(node) {
        if (!node)
            return "App";
        var p = node.properties || {};
        return String(p["application.name"] || p["media.name"] || node.description || node.name || "App");
    }
    function appIcon(node) {
        var p = (node && node.properties) || {};
        var n = String(p["application.icon-name"] || p["application.name"] || "");
        if (n.length === 0)
            return "";
        return Quickshell.iconPath(n.toLowerCase(), "application-x-executable");
    }
    // Device-type glyph from the device description/name. Codepoints are
    // render-verified in Task 5 (candidates here).
    function typeGlyph(node) {
        var s = String((node && (node.description || node.name)) || "").toLowerCase();
        if (s.indexOf("hdmi") !== -1 || s.indexOf("display") !== -1 || s.indexOf("monitor") !== -1)
            return String.fromCodePoint(0xF0379); // monitor
        if (s.indexOf("headphone") !== -1 || s.indexOf("headset") !== -1 || s.indexOf("buds") !== -1)
            return String.fromCodePoint(0xF02CB); // headphones
        if (s.indexOf("mic") !== -1 || s.indexOf("source") !== -1)
            return String.fromCodePoint(0xF036C); // microphone
        return String.fromCodePoint(0xF04C3); // speaker
    }
    // Volume level glyph. Codepoints are render-verified in Task 2.
    function volumeGlyph(vol, muted) {
        if (muted || vol <= 0)
            return String.fromCodePoint(0xF0581); // volume-mute
        if (vol < 34)
            return String.fromCodePoint(0xF057F); // volume-low
        if (vol < 67)
            return String.fromCodePoint(0xF0580); // volume-medium
        return String.fromCodePoint(0xF057E); // volume-high
    }
}
