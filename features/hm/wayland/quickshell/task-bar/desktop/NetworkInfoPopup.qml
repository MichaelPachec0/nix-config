import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib

// WiFi detail popup, shown on hover over the bar widget. All data is read-only
// D-Bus: NetworkManager (BSSID, signal %, freq/channel, security, rate, IP) plus
// wpa_supplicant SignalPoll (RSSI dBm, noise, linkspeed, width) -- the latter
// needs the read-only dbus policy on thanatos; until then those read "N/A".
// Country code and PHY/protocol are not on D-Bus -> "N/A" pending a future `iw`
// add. See memory wifi-widget-iw-followup.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var net // Lib.NetworkService
    property string title: ""

    property var info: ({})

    implicitWidth: 280
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: false // a tooltip; must not steal focus

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    function show() {
        if (pop.visible)
            return;
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = x;
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }
    function hide() {
        pop.visible = false;
    }

    // --- helpers ---
    function chFromFreq(f) {
        f = f || 0;
        if (f >= 5955)
            return (f - 5950) / 5;
        if (f >= 5000)
            return (f - 5000) / 5;
        if (f === 2484)
            return 14;
        if (f >= 2412)
            return (f - 2407) / 5;
        return 0;
    }
    function band(f) {
        f = f || 0;
        return f >= 5955 ? "6G" : (f >= 5000 ? "5G" : "2.4G");
    }
    function decodeSec(rsn, wpa) {
        rsn = rsn || 0;
        wpa = wpa || 0;
        if (rsn === 0 && wpa === 0)
            return "Open";
        var f = rsn || wpa;
        var mgmt = [];
        if (f & 0x400)
            mgmt.push("WPA3");
        if (f & 0x100)
            mgmt.push("WPA2");
        if (f & 0x200)
            mgmt.push("Enterprise");
        if (f & 0x800)
            mgmt.push("OWE");
        if (mgmt.length === 0)
            mgmt.push(rsn ? "WPA2" : "WPA");
        var ciph = (f & 0x88) ? "CCMP" : ((f & 0x44) ? "TKIP" : "");
        return mgmt.join("/") + (ciph ? " (" + ciph + ")" : "");
    }
    function rateStr() {
        var i = pop.info;
        if (i.linkspeed)
            return i.linkspeed + " Mbit/s";
        if (i.rate)
            return Math.round(i.rate / 1000) + " Mbit/s";
        return "N/A";
    }

    // "36 (5G: 5180MHz, 80MHz)" -- channel + band + freq + width in one line.
    function channelStr() {
        var i = pop.info;
        if (!i.freq)
            return "N/A";
        var w = i.width ? ", " + String(i.width).replace(/\s/g, "") : "";
        return pop.chFromFreq(i.freq) + " (" + pop.band(i.freq) + ": " + i.freq + "MHz" + w + ")";
    }

    // label/value rows, recomputed when info changes. Always-present rows first,
    // then RF rows only when not on Ethernet.
    readonly property var rows: {
        var i = pop.info;
        var base = [
            {
                k: "IP",
                v: (pop.net.ip || i.ip || "N/A")
            },
            {
                k: "Router",
                v: (pop.net.gateway || i.gw || "N/A")
            },
            {
                k: "Internet",
                v: pop.net.connectivity,
                color: (pop.net.connectivity === "full" ? pop.theme.accentGreen : pop.net.connectivity === "limited" ? pop.theme.accentOrange : pop.net.connectivity === "portal" ? pop.theme.accentYellow : pop.net.connectivity === "none" ? pop.theme.accentRed : pop.theme.textPrimary)
            },
            {
                k: "VPN",
                v: (pop.net.vpnActive ? pop.net.vpns.filter(function (x) {
                        return x.active;
                    }).map(function (x) {
                        return x.name;
                    }).join(", ") : "Off")
            }
        ];
        if (pop.net.primaryType === "ethernet")
            return base;
        return base.concat([
            {
                k: "Signal",
                v: (i.signal !== undefined ? (i.signal + "%" + (i.rssi !== undefined ? " (" + i.rssi + " dBm)" : "")) : (i.rssi !== undefined ? i.rssi + " dBm" : "N/A"))
            },
            {
                k: "Noise",
                v: (i.noise !== undefined && i.noise < 0 && i.noise > -200 ? i.noise + " dBm" : "N/A")
            },
            {
                k: "Rate",
                v: pop.rateStr()
            },
            {
                k: "Security",
                v: pop.decodeSec(i.rsn, i.wpa)
            },
            {
                k: "BSSID",
                v: (pop.net.bssid || i.bssid || "N/A")
            },
            {
                k: "Channel",
                v: pop.channelStr()
            },
            {
                k: "Country",
                v: "N/A"
            } // regdomain not on D-Bus -> needs iw (deferred)
            ,
            {
                k: "PHY",
                v: (i.phy || "N/A")
            }
        ]);
    }

    Lib.CommandPoll {
        id: poll
        interval: 3000
        running: pop.visible
        command: ["bash", "-c", `
IFACE=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
[ -z "$IFACE" ] && exit 0
NM=org.freedesktop.NetworkManager
gp(){ busctl --system get-property "$NM" "$1" "$2" "$3" 2>/dev/null; }
DEV=$(busctl --system call "$NM" /org/freedesktop/NetworkManager "$NM" GetDeviceByIpIface s "$IFACE" 2>/dev/null | awk '{print $NF}' | tr -d '"')
[ -z "$DEV" ] && exit 0
AP=$(gp "$DEV" "$NM.Device.Wireless" ActiveAccessPoint | awk '{print $NF}' | tr -d '"')
[ -z "$AP" -o "$AP" = "/" ] && exit 0
echo "BSSID:$(gp "$AP" "$NM.AccessPoint" HwAddress | sed -E 's/^s //; s/"//g')"
echo "SIGNAL:$(gp "$AP" "$NM.AccessPoint" Strength | awk '{print $NF}')"
echo "FREQ:$(gp "$AP" "$NM.AccessPoint" Frequency | awk '{print $NF}')"
echo "RATE:$(gp "$DEV" "$NM.Device.Wireless" Bitrate | awk '{print $NF}')"
echo "RSN:$(gp "$AP" "$NM.AccessPoint" RsnFlags | awk '{print $NF}')"
echo "WPA:$(gp "$AP" "$NM.AccessPoint" WpaFlags | awk '{print $NF}')"
echo "IP:$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
echo "GW:$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}')"
WPAIF=$(busctl --system call fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 GetInterface s "$IFACE" 2>/dev/null | awk '{print $NF}' | tr -d '"')
if [ -n "$WPAIF" ]; then
  SP=$(busctl --system call fi.w1.wpa_supplicant1 "$WPAIF" fi.w1.wpa_supplicant1.Interface SignalPoll 2>/dev/null)
  echo "RSSI:$(printf '%s' "$SP" | grep -oE '"rssi" [a-z] -?[0-9]+' | awk '{print $NF}')"
  echo "NOISE:$(printf '%s' "$SP" | grep -oE '"noise" [a-z] -?[0-9]+' | awk '{print $NF}')"
  echo "LINKSPEED:$(printf '%s' "$SP" | grep -oE '"linkspeed" [a-z] -?[0-9]+' | awk '{print $NF}')"
  echo "WIDTH:$(printf '%s' "$SP" | grep -oE '"width" s "[^"]+"' | sed -E 's/.*"([^"]+)"$/\\1/')"
  if echo "$SP" | grep -q 'eht-mcs'; then echo "PHY:802.11be (Wi-Fi 7)"
  elif echo "$SP" | grep -q 'he-mcs'; then echo "PHY:802.11ax (Wi-Fi 6)"
  elif echo "$SP" | grep -q 'vht-mcs'; then echo "PHY:802.11ac (Wi-Fi 5)"
  elif echo "$SP" | grep -q 'ht-mcs'; then echo "PHY:802.11n (Wi-Fi 4)"
  else echo "PHY:802.11a/g"; fi
fi
`]
        parse: function (o) {
            var r = {};
            String(o).split(/\r?\n/).forEach(function (line) {
                var i = line.indexOf(":");
                if (i < 0)
                    return;
                var k = line.slice(0, i);
                var v = line.slice(i + 1).trim();
                if (v === "")
                    return;
                if (k === "BSSID")
                    r.bssid = v;
                else if (k === "SIGNAL")
                    r.signal = parseInt(v, 10);
                else if (k === "FREQ")
                    r.freq = parseInt(v, 10);
                else if (k === "RATE")
                    r.rate = parseInt(v, 10);
                else if (k === "RSN")
                    r.rsn = parseInt(v, 10);
                else if (k === "WPA")
                    r.wpa = parseInt(v, 10);
                else if (k === "IP")
                    r.ip = v;
                else if (k === "GW")
                    r.gw = v;
                else if (k === "RSSI")
                    r.rssi = parseInt(v, 10);
                else if (k === "NOISE")
                    r.noise = parseInt(v, 10);
                else if (k === "LINKSPEED")
                    r.linkspeed = parseInt(v, 10);
                else if (k === "WIDTH")
                    r.width = v;
                else if (k === "PHY")
                    r.phy = v;
            });
            return r;
        }
        onUpdated: pop.info = value
    }

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 20
        radius: 11
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: pop.title || "Wi-Fi"
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            Repeater {
                model: pop.rows
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: modelData.k
                        color: pop.theme.textSecondary
                        font.family: pop.theme.textFont
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.v
                        color: modelData.color || pop.theme.textPrimary
                        font.family: pop.theme.textFont
                        font.pixelSize: 11
                        elide: Text.ElideLeft
                    }
                }
            }
        }
    }
}
