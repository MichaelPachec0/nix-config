pragma ComponentBehavior: Bound
import QtQml
import Quickshell

// Shared network state for the bar widget + popups: radio/connectivity, the
// primary connection (wired or Wi-Fi) with SSID/BSSID/IP/gateway/signal/name,
// and the list of non-Wi-Fi connection profiles (ethernet/VPN/WireGuard/...).
// One bash poll (nmcli + ip) emits K:V lines (plus CONN: lines). Mirrors
// AudioService/MprisExtras: actions update locally first, then fire nmcli +
// re-poll. "Primary" = the device carrying the default route.
QtObject {
    id: svc

    property bool hasWifi: false
    property bool wifiRadio: false
    property string primaryType: "none" // "wifi" | "ethernet" | "none"
    property string connState: "disconnected" // "activating" | "activated" | ...
    property string ssid: ""
    property string bssid: ""
    property string ip: ""
    property string gateway: ""
    property string iface: ""
    property string connName: ""
    property int signalVal: 0 // "signal" is a reserved QML keyword
    property string connectivity: "unknown" // full|limited|portal|none|unknown
    property string wifiUuid: "" // active Wi-Fi connection uuid (for disconnect)
    property var conns: [] // [{uuid,name,type,active,ip,gateway}] -- all non-Wi-Fi profiles
    // VPN/WireGuard subset of conns, for the bar shield + info-panel VPN row.
    readonly property var vpns: {
        var r = [];
        for (var i = 0; i < svc.conns.length; ++i) {
            var c = svc.conns[i];
            if (c.type === "vpn" || c.type === "wireguard")
                r.push(c);
        }
        return r;
    }
    // Instantaneous "any VPN/WireGuard profile up" from the latest poll.
    readonly property bool vpnUpRaw: {
        for (var i = 0; i < svc.vpns.length; ++i)
            if (svc.vpns[i].active)
                return true;
        return false;
    }
    // Latched VPN state driving the bar shield. Going UP is immediate; going DOWN
    // is held ~6s (survives one missed 4s poll) so a WireGuard/VPN rekey -- which
    // momentarily reports the profile down -- doesn't blink the shield off/on.
    property bool vpnActive: false
    onVpnUpRawChanged: {
        if (svc.vpnUpRaw) {
            svc.vpnActive = true;
            svc._vpnLatch.stop();
        } else {
            svc._vpnLatch.restart();
        }
    }
    property Timer _vpnLatch: Timer {
        interval: 6000
        repeat: false
        onTriggered: svc.vpnActive = svc.vpnUpRaw
    }
    readonly property var ethernetConns: {
        var r = [];
        for (var i = 0; i < svc.conns.length; ++i)
            if (svc.conns[i].type === "802-3-ethernet")
                r.push(svc.conns[i]);
        return r;
    }

    function refresh() {
        svc.statusPoll.poll();
    }

    function disconnect() {
        if (svc.wifiUuid === "")
            return;
        svc.connState = "disconnected"; // optimistic
        svc.ssid = "";
        Quickshell.execDetached(["nmcli", "con", "down", "uuid", svc.wifiUuid]);
        svc.statusPoll.poll();
    }
    function toggleConn(uuid, up) {
        if (!uuid)
            return;
        svc.conns = svc.conns.map(function (x) {
            return x.uuid === uuid ? Object.assign({}, x, {
                "active": up
            }) : x;
        });
        Quickshell.execDetached(["nmcli", "con", up ? "up" : "down", "uuid", uuid]);
        svc.statusPoll.poll();
    }

    function defaultTab() {
        var wifiUp = svc.hasWifi && svc.connState === "activated" && svc.primaryType === "wifi";
        var ethUp = false;
        for (var i = 0; i < svc.ethernetConns.length; ++i)
            if (svc.ethernetConns[i].active) {
                ethUp = true;
                break;
            }
        if (!wifiUp && ethUp)
            return "ethernet";
        if (svc.hasWifi)
            return "wifi";
        if (svc.ethernetConns.length > 0)
            return "ethernet";
        if (svc.vpns.length > 0)
            return "vpn";
        return "wifi";
    }

    function _parse(o) {
        var r = {
            wifiRadio: false,
            hasWifi: false,
            connectivity: "unknown",
            primaryType: "none",
            connState: "disconnected",
            ssid: "",
            bssid: "",
            ip: "",
            gateway: "",
            iface: "",
            connName: "",
            signal: 0,
            wifiUuid: "",
            conns: []
        };
        String(o).split(/\r?\n/).forEach(function (line) {
            if (line.indexOf("CONN:") === 0) {
                var p = line.slice(5).split("|");
                if (p.length >= 4)
                    r.conns.push({
                        "uuid": p[0],
                        "name": p[1],
                        "type": p[2],
                        "active": p[3] === "up",
                        "ip": p.length > 4 ? p[4] : "",
                        "gateway": p.length > 5 ? p[5] : ""
                    });
                return;
            }
            var i = line.indexOf(":");
            if (i < 0)
                return;
            var k = line.slice(0, i);
            var v = line.slice(i + 1).trim();
            if (k === "WIFI")
                r.wifiRadio = (v === "enabled");
            else if (k === "HASWIFI")
                r.hasWifi = (v === "1");
            else if (k === "CONNECTIVITY")
                r.connectivity = v || "unknown";
            else if (k === "PTYPE")
                r.primaryType = v || "none";
            else if (k === "STATE")
                r.connState = v;
            else if (k === "SSID")
                r.ssid = v;
            else if (k === "BSSID")
                r.bssid = v;
            else if (k === "IP")
                r.ip = v;
            else if (k === "GW")
                r.gateway = v;
            else if (k === "IFACE")
                r.iface = v;
            else if (k === "CNAME")
                r.connName = v;
            else if (k === "SIGNAL")
                r.signal = parseInt(v, 10) || 0;
            else if (k === "WUUID")
                r.wifiUuid = v;
        });
        return r;
    }
    function _apply(v) {
        svc.wifiRadio = v.wifiRadio;
        svc.hasWifi = v.hasWifi;
        svc.connectivity = v.connectivity;
        svc.primaryType = v.primaryType;
        svc.connState = v.connState;
        svc.ssid = v.ssid;
        svc.bssid = v.bssid;
        svc.ip = v.ip;
        svc.gateway = v.gateway;
        svc.iface = v.iface;
        svc.connName = v.connName;
        svc.signalVal = v.signal;
        svc.wifiUuid = v.wifiUuid;
        svc.conns = v.conns;
    }

    property CommandPoll statusPoll: CommandPoll {
        interval: 4000
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/net-status.sh"]
        parse: svc._parse
        onUpdated: svc._apply(this.value)
    }
}
