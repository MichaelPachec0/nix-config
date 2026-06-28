pragma ComponentBehavior: Bound
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Shared, reactive Bluetooth state for the bar widget, dropdown and tooltip.
// Wraps the native Quickshell.Bluetooth default adapter and derives the three
// device buckets (connected / paired-offline / discovered) the UI renders.
// Centralizing the watcher avoids duplicating per-device reactivity across the
// three surfaces (cf. lib/NotifService.qml). Instantiated once at ShellRoot.
QtObject {
    id: svc

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: svc.adapter !== null
    readonly property bool enabled: svc.available && svc.adapter.enabled
    readonly property bool discovering: svc.available && svc.adapter.discovering
    readonly property bool blocked: svc.available && svc.adapter.state === BluetoothAdapterState.Blocked
    readonly property string adapterId: svc.available ? svc.adapter.adapterId : ""

    // Bumped whenever a device property the UI cares about changes, so the
    // derived arrays recompute. (ObjectModel.values' own NOTIFY only fires on
    // add/remove, not on a device's connected/paired/battery changing.)
    property int bump: 0

    readonly property var devices: {
        svc.bump; // dependency: re-eval on per-device property changes
        return svc.available ? svc.adapter.devices.values : [];
    }
    readonly property var connectedDevices: svc.devices.filter(function (d) {
        return d.connected;
    })
    readonly property var pairedDevices: svc.devices.filter(function (d) {
        return d.paired && !d.connected;
    })
    readonly property var discoveredDevices: svc.devices.filter(function (d) {
        return !d.paired;
    })
    // Discovered split: devices that broadcast a Name vs. address-only. BlueZ
    // leaves `Name` (-> deviceName) empty for nameless devices, so deviceName
    // being non-empty is the test; `name`/Alias falls back to the MAC.
    readonly property var discoveredNamed: svc.discoveredDevices.filter(function (d) {
        return String(d.deviceName || "").length > 0;
    })
    readonly property var discoveredUnnamed: svc.discoveredDevices.filter(function (d) {
        return String(d.deviceName || "").length === 0;
    })

    // --- Connected-device audio + earbud data (shared by the menu detail panel
    // and the bar hover panel). PipeWire codec/profile/volume for any audio
    // device; pbpctrl settings for Pixel Buds. Centralized here so pbpctrl is
    // driven by ONE serial owner -- it cannot run concurrently and a call killed
    // mid-RFCOMM wedges the channel, so we never overlap and never kill.
    readonly property var primaryAudio: svc.connectedDevices.length > 0 ? svc.connectedDevices[0] : null
    readonly property string audioMac: svc.primaryAudio ? String(svc.primaryAudio.address) : ""
    readonly property bool audioIsBuds: svc.primaryAudio ? /pixel buds/i.test(String(svc.primaryAudio.deviceName || svc.primaryAudio.name || "")) : false
    // Panels set these while visible; we only poll while something wants the data.
    property bool hoverWants: false
    property bool menuWants: false
    readonly property bool audioWanted: svc.hoverWants || svc.menuWants

    property var pw: ({})  // { codec, profile, volume }
    property var pbp: ({}) // { left,right,case,anc,multipoint,ohd,volumeeq,mono,speech,balance,eq,firmware }

    function parseKV(out) {
        var m = {};
        var lines = String(out || "").trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
            var idx = lines[i].indexOf("=");
            if (idx > 0)
                m[lines[i].slice(0, idx)] = lines[i].slice(idx + 1).trim();
        }
        return m;
    }

    // PipeWire poll (safe to run freely; independent of pbpctrl).
    property CommandPoll pwPoll: CommandPoll {
        interval: 4000
        running: svc.audioWanted && svc.audioMac !== ""
        command: ["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/btinfo.sh pw " + svc.audioMac]
        parse: function (out) {
            return svc.parseKV(out);
        }
        onUpdated: svc.pw = this.value
    }

    // pbpctrl serial executor: one Process drains a queue of read/write jobs so
    // calls never overlap. A 30s timer enqueues a read; pbpSet() enqueues a
    // write followed by a confirming read.
    property var pbpJobs: []
    property bool pbpBusy: false
    property bool pbpCurRead: false
    function pbpEnqueue(argstr, isRead) {
        svc.pbpJobs = svc.pbpJobs.concat([{
            "a": argstr,
            "r": isRead
        }]);
        svc.pbpKick();
    }
    function pbpKick() {
        if (svc.pbpBusy || svc.pbpJobs.length === 0)
            return;
        svc.pbpBusy = true;
        var j = svc.pbpJobs[0];
        svc.pbpJobs = svc.pbpJobs.slice(1);
        svc.pbpCurRead = j.r;
        svc.pbpProc.exec(["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/btinfo.sh " + j.a]);
    }
    // Switch the A2DP codec (PipeWire card profile -- fast, no pbpctrl/RFCOMM).
    function codecSet(prof) {
        if (svc.audioMac === "" || !prof)
            return;
        Quickshell.execDetached(["bash", "-lc", "$HOME/.config/quickshell/task-bar/lib/btinfo.sh codec " + svc.audioMac + " " + prof]);
    }

    // setting: e.g. "anc"; vals: space-joined values e.g. "active" or "1 0 -1 2 0".
    function pbpSet(setting, vals) {
        if (svc.audioMac === "")
            return;
        svc.pbpEnqueue("set " + svc.audioMac + " " + setting + " " + vals, false);
        svc.pbpEnqueue("pbp " + svc.audioMac, true);
    }
    property Process pbpProc: Process {
        stdout: StdioCollector {
            onStreamFinished: if (svc.pbpCurRead)
                svc.pbp = svc.parseKV(this.text)
        }
        onExited: {
            svc.pbpBusy = false;
            svc.pbpKick();
        }
    }
    property Timer pbpTimer: Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: svc.audioWanted && svc.audioMac !== "" && svc.audioIsBuds
        onTriggered: {
            var hasRead = svc.pbpJobs.some(function (j) {
                return j.r;
            });
            if (!hasRead)
                svc.pbpEnqueue("pbp " + svc.audioMac, true);
        }
    }

    // Address of a just-paired device to auto-connect once pairing completes.
    property string pendingConnectAddr: ""

    function setEnabled(on) {
        if (svc.available)
            svc.adapter.enabled = on;
    }
    function setDiscovering(on) {
        if (svc.available)
            svc.adapter.discovering = on;
    }
    // Discovered-row click: pair, then connect when pairing lands (handled in
    // the per-device watcher below).
    function pairAndConnect(dev) {
        if (!dev)
            return;
        if (dev.paired) {
            dev.connect();
            return;
        }
        svc.pendingConnectAddr = dev.address;
        dev.pair();
    }

    // Map a freedesktop device icon name to a monochrome Nerd Font glyph. Glyph
    // codepoints are render-test verified in Task 6; the values here are the
    // starting candidates.
    function typeGlyph(icon) {
        var s = String(icon || "");
        if (s.indexOf("headset") !== -1 || s.indexOf("headphone") !== -1)
            return String.fromCodePoint(0xF02CB); // headphones
        if (s.indexOf("speaker") !== -1 || s === "audio-card")
            return String.fromCodePoint(0xF04C3); // speaker
        if (s.indexOf("mouse") !== -1)
            return String.fromCodePoint(0xF037D); // mouse
        if (s.indexOf("keyboard") !== -1)
            return String.fromCodePoint(0xF030C); // keyboard
        if (s.indexOf("gaming") !== -1 || s.indexOf("joystick") !== -1)
            return String.fromCodePoint(0xF02B4); // controller
        if (s.indexOf("phone") !== -1)
            return String.fromCodePoint(0xF011C); // cellphone
        if (s.indexOf("computer") !== -1 || s.indexOf("laptop") !== -1)
            return String.fromCodePoint(0xF0322); // laptop
        if (s.indexOf("printer") !== -1)
            return String.fromCodePoint(0xF042A); // printer
        return String.fromCodePoint(0xF00AF); // generic bluetooth
    }

    // Attach to every device; bump on the relevant property changes and finish
    // a pending pair->connect. Instantiator (non-visual) manages one delegate
    // per device across add/remove, so the Connections lifecycle tracks the
    // model. Per-device add/remove also re-fires `devices` via values' NOTIFY.
    property Instantiator watcher: Instantiator {
        model: svc.available ? svc.adapter.devices : null
        delegate: QtObject {
            required property var modelData
            property Connections c: Connections {
                target: modelData
                function onConnectedChanged() {
                    svc.bump++;
                }
                function onPairedChanged() {
                    svc.bump++;
                    if (modelData.paired && modelData.address === svc.pendingConnectAddr) {
                        svc.pendingConnectAddr = "";
                        modelData.connect();
                    }
                }
                function onBondedChanged() {
                    svc.bump++;
                }
                function onBatteryChanged() {
                    svc.bump++;
                }
                function onStateChanged() {
                    svc.bump++;
                }
            }
        }
    }
}
