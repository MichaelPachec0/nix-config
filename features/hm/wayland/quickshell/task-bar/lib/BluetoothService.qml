pragma ComponentBehavior: Bound
import QtQml
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
        if (s.indexOf("watch") !== -1)
            return String.fromCodePoint(0xF00D5); // watch
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
