// features/hm/wayland/quickshell/task-bar/lock/LockNetwork.qml
// Connectivity block, top-left on the lock, between the battery block and the
// security column. Link, internet reachability, VPN, cellular uplink and
// connected Bluetooth devices.
//
// Every value comes from a shell-global service that shell.qml already
// instantiates and polls (NetworkService, RouterService, BluetoothService), so
// this block adds no poll and no script. Both network polls already run while
// locked.
//
// NOT part of LockSecurity, deliberately: that column is metadata only --
// counts, times, session numbers, nothing that renders a name. The SSID and
// Bluetooth device names here break that rule by design, which is why they
// live in their own component with their own privacy switches.
//
// All text-producing logic is in the pure functions below, taking explicit
// arguments rather than reading the services, because a headless fixture
// cannot inject NetworkManager, BlueZ, or a router status file.
//
// `qualityFn` is injected rather than imported (LockSurface passes
// RouterFmt.quality) because `import "../lib/routerfmt.js"` fails when
// locknet-test.qml is the quickshell -p entrypoint -- the entrypoint's parent
// becomes the config root, putting lib/ outside it. Same pattern and same
// reason as LockSecurity's stampFn.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property var theme: null
    property real contentOpacity: 1.0
    property bool showSsid: true
    property bool showRouter: true
    property bool showBluetooth: true
    // RouterFmt.quality, injected by LockSurface -- see the header note.
    property var qualityFn: null

    spacing: 2
    opacity: root.contentOpacity

    // --- pure core (covered by locknet-test.qml) --------------------------

    // Wifi signal is a PERCENT (nmcli -g SIGNAL), never dBm. Hiding the SSID
    // keeps the percentage: the number is not identifying, and it is half the
    // value of the row.
    function _linkText(primaryType, connState, ssid, signalPct, showSsid) {
        if (String(connState) === "activating")
            return "Connecting";
        if (String(connState) !== "activated")
            return "Disconnected";
        if (String(primaryType) === "ethernet")
            return "Ethernet";
        if (String(primaryType) !== "wifi")
            return "Disconnected";
        var name = (showSsid && String(ssid || "").length > 0) ? String(ssid) : "Connected";
        return name + "  " + Math.round(Number(signalPct) || 0) + "%";
    }

    // Separate from the link row, not a modifier on it: the common captive
    // portal case is a healthy association with no internet behind it, and
    // merging them would force picking one to report.
    function _troubleText(connectivity, linkUp) {
        if (!linkUp)
            return ""; // a disconnected machine has no internet by definition
        var c = String(connectivity || "");
        if (c === "portal")
            return "Captive portal";
        // "unknown" is NOT trouble: NetworkManager reports it before its first
        // check and when checking is disabled, so treating it as an outage
        // would fire on every boot and make the red row routine.
        if (c === "limited" || c === "none")
            return "No internet";
        return "";
    }

    function _vpnText(vpns) {
        var names = [];
        var list = vpns || [];
        for (var i = 0; i < list.length; i++)
            if (list[i] && list[i].active)
                names.push(String(list[i].name || "vpn"));
        return names.length > 0 ? ("VPN: " + names.join(", ")) : "";
    }

    // Gated on `supported` -- what the collector sets from whether the modem
    // returned a signal list at all -- rather than on any single metric being
    // present. Each part drops out on its own when null; `operator` is null
    // whenever no cell is camped, and "Unknown 5G" reads as a fault.
    function _cellText(cellular) {
        var c = cellular || {};
        if (c.supported !== true)
            return "";
        var head = [];
        if (c.operator)
            head.push(String(c.operator));
        if (c.gen)
            head.push(String(c.gen));
        var left = head.join(" ");
        var rsrp = (c.rsrp === null || c.rsrp === undefined) ? "" : (c.rsrp + " dBm");
        if (left && rsrp)
            return left + "  " + rsrp;
        return left || rsrp;
    }

    // Tint from SINR, not RSRP. A congested cell a few metres away reports
    // excellent rsrp and poor sinr while throughput collapses; tinting on rsrp
    // would call that healthy, which is the everyday failure this row exists
    // to expose.
    function _cellQuality(cellular) {
        var c = cellular || {};
        // Guard BEFORE calling quality(): it answers "poor" for a null value,
        // which would paint a warning tint on a router that simply has no
        // reading yet. No reading, no verdict.
        if (c.sinr === null || c.sinr === undefined || isNaN(c.sinr))
            return "";
        if (!root.qualityFn)
            return "";
        return root.qualityFn("sinr", c.sinr);
    }

    // Which quality bands are worth a colour. "fair" is included: sinr below
    // 6 dB is where throughput starts falling off a cliff, and a row that only
    // warns at "poor" would stay grey through the part of the range the user
    // could still act on. "" (no reading) never warns.
    function _cellNeedsWarn(q) {
        return q === "fair" || q === "poor";
    }

    // BlueZ leaves Name empty for nameless devices, so fall back to the
    // address rather than emitting an empty entry and a stray comma.
    function _btText(devices) {
        var out = [];
        var list = devices || [];
        for (var i = 0; i < list.length; i++) {
            var d = list[i] || {};
            var n = String(d.deviceName || "") || String(d.name || "") || String(d.address || "");
            if (n)
                out.push(n);
        }
        return out.join(", ");
    }
}
