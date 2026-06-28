pragma ComponentBehavior: Bound
import QtQml
import Quickshell

// Shared network state for the bar widget + popups: radio/connectivity, the
// primary connection (wired or Wi-Fi) with SSID/BSSID/IP/gateway/signal/name,
// and the VPN connection list. One bash poll (nmcli + ip) emits K:V lines (plus
// VPN: lines). Mirrors AudioService/MprisExtras: actions update locally first,
// then fire nmcli + re-poll. "Primary" = the device carrying the default route.
QtObject {
    id: svc

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
    property var vpns: [] // [{uuid,name,active}]
    readonly property bool vpnActive: {
        for (var i = 0; i < svc.vpns.length; ++i)
            if (svc.vpns[i].active)
                return true;
        return false;
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
    function toggleVpn(uuid, up) {
        if (!uuid)
            return;
        svc.vpns = svc.vpns.map(function (x) {
            return x.uuid === uuid ? Object.assign({}, x, {
                "active": up
            }) : x;
        });
        Quickshell.execDetached(["nmcli", "con", up ? "up" : "down", "uuid", uuid]);
        svc.statusPoll.poll();
    }

    function _parse(o) {
        var r = {
            wifiRadio: false,
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
            vpns: []
        };
        String(o).split(/\r?\n/).forEach(function (line) {
            if (line.indexOf("VPN:") === 0) {
                var p = line.slice(4).split("|");
                if (p.length >= 3)
                    r.vpns.push({
                        "uuid": p[0],
                        "name": p[1],
                        "active": p[2] === "up"
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
        svc.vpns = v.vpns;
    }

    property CommandPoll statusPoll: CommandPoll {
        interval: 4000
        command: ["bash", "-c", `
WIFI=$(nmcli -g WIFI radio 2>/dev/null || echo unknown); echo "WIFI:$WIFI"
echo "CONNECTIVITY:$(nmcli -g CONNECTIVITY general status 2>/dev/null)"
PDEV=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
echo "IFACE:$PDEV"
echo "IP:$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
echo "GW:$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}')"
PTYPE=none
if [ -n "$PDEV" ]; then
  T=$(nmcli -g GENERAL.TYPE device show "$PDEV" 2>/dev/null)
  case "$T" in wifi) PTYPE=wifi;; ethernet) PTYPE=ethernet;; *) PTYPE="$T";; esac
  echo "CNAME:$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$PDEV" '$2==d{print $1; exit}')"
fi
echo "PTYPE:$PTYPE"
WROW=$(nmcli -t -f UUID,TYPE,STATE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print; exit}')
WUUID=$(printf '%s' "$WROW" | cut -d: -f1)
echo "WUUID:$WUUID"
if [ -n "$WUUID" ]; then
  WSTATE=$(printf '%s' "$WROW" | cut -d: -f3)
  [ "$WSTATE" = "activated" ] && echo "STATE:activated" || echo "STATE:activating"
  echo "SSID:$(nmcli -g 802-11-wireless.ssid connection show uuid "$WUUID" 2>/dev/null | head -n1)"
  echo "SIGNAL:$(nmcli -g IN-USE,SIGNAL dev wifi list 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')"
  echo "BSSID:$(nmcli -g IN-USE,BSSID dev wifi list 2>/dev/null | sed -n 's/^\*://p' | head -n1 | tr -d '\\')"
elif [ "$PTYPE" = "ethernet" ]; then
  echo "STATE:activated"
else
  echo "STATE:disconnected"
fi
ACT=$(nmcli -t -f UUID connection show --active 2>/dev/null)
nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r u t; do
  case "$t" in vpn|wireguard) ;; *) continue;; esac
  n=$(nmcli -g connection.id connection show uuid "$u" 2>/dev/null)
  st=down; printf '%s\n' "$ACT" | grep -qx "$u" && st=up
  echo "VPN:$u|$n|$st"
done
`]
        parse: svc._parse
        onUpdated: svc._apply(this.value)
    }
}
