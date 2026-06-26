import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../lib" as Lib

// WiFi click menu (step 4b): header (Wi-Fi on/off + rescan) and a scrollable,
// deduped, signal-sorted network list (strength glyph, lock for secured, check
// for the connected one). Clicking connects to open/saved networks; the
// password prompt for new secured networks + disconnect/forget land in 4c/4d.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    property bool wifiEnabled: false
    property var networks: []

    implicitWidth: 280
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: true
    onVisibleChanged: if (!pop.visible)
        apInfo.hide()

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    // Per-AP detail tooltip, shown to the left of the menu on row hover.
    ApInfoPopup {
        id: apInfo
        theme: pop.theme
        menuWindow: pop
    }

    function toggle() {
        if (pop.visible) {
            pop.visible = false;
            return;
        }
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = x;
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }
    function det(cmd) {
        Quickshell.execDetached(["bash", "-lc", cmd]);
    }
    function netGlyph(signal) {
        if (signal <= 25)
            return String.fromCodePoint(0xF091F);
        if (signal <= 50)
            return String.fromCodePoint(0xF0922);
        if (signal <= 75)
            return String.fromCodePoint(0xF0925);
        return String.fromCodePoint(0xF0928);
    }

    Lib.CommandPoll {
        id: scan
        interval: 6000
        running: pop.visible && pop.wifiEnabled
        command: ["bash", "-lc", `
nmcli -t -f IN-USE,SIGNAL,SECURITY,CHAN,FREQ,RATE,BANDWIDTH,MODE,RSN-FLAGS,BSSID,SSID dev wifi list 2>/dev/null
IFACE=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
WPAIF=$(busctl --system call fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 GetInterface s "$IFACE" 2>/dev/null | awk '{print $2}' | tr -d '"')
if [ -n "$WPAIF" ]; then
  BSSES=$(busctl --system get-property fi.w1.wpa_supplicant1 "$WPAIF" fi.w1.wpa_supplicant1.Interface BSSs 2>/dev/null | grep -oE '/fi/w1/wpa_supplicant1/[^" ]*/BSSs/[0-9]+')
  for b in $BSSES; do busctl --system call fi.w1.wpa_supplicant1 "$b" org.freedesktop.DBus.Properties GetAll s fi.w1.wpa_supplicant1.BSS 2>/dev/null; done | awk '
{
  bssid=""; sig=""; age="";
  for(i=1;i<=NF;i++){
    if($i ~ /^"BSSID"$/){ cnt=$(i+2); s=""; for(j=1;j<=cnt;j++){ s=s sprintf("%s%02X",(j>1?":":""),$(i+2+j)); } bssid=s; }
    else if($i ~ /^"Signal"$/){ sig=$(i+2); }
    else if($i ~ /^"Age"$/){ age=$(i+2); }
  }
  if(bssid!="") print "WBSS:" bssid ":" sig ":" age;
}'
fi
`]
        parse: function (o) {
            var seen = {};
            var nets = [];
            var wbss = {}; // BSSID -> {dbm, age} from wpa_supplicant
            String(o).split(/\r?\n/).forEach(function (line) {
                if (!line)
                    return;
                if (line.indexOf("WBSS:") === 0) {
                    var w = line.split(":"); // WBSS:46:A5:..:18:-40:12
                    if (w.length >= 9)
                        wbss[w.slice(1, 7).join(":").toUpperCase()] = {
                            dbm: parseInt(w[7], 10),
                            age: parseInt(w[8], 10)
                        };
                    return;
                }
                // nmcli -t escapes ':' in values as '\:' -> sentinel-swap, split,
                // restore. Fields: IN-USE,SIGNAL,SECURITY,CHAN,FREQ,RATE,
                // BANDWIDTH,MODE,RSN-FLAGS,BSSID,SSID.
                var parts = line.replace(/\\:/g, "@@C@@").split(":");
                if (parts.length < 11)
                    return;
                for (var j = 0; j < parts.length; j++)
                    parts[j] = parts[j].replace(/@@C@@/g, ":");
                var ssid = parts.slice(10).join(":");
                if (!ssid)
                    return; // hidden network
                var inuse = parts[0].trim() === "*";
                var signal = parseInt(parts[1], 10) || 0;
                var rsn = parts[8];
                var secured = (rsn !== "" && rsn !== "(none)") || (parts[2] !== "" && parts[2] !== "--");
                var n = {
                    ssid: ssid,
                    signal: signal,
                    secured: secured,
                    inuse: inuse,
                    chan: parts[3],
                    freq: parseInt(parts[4], 10) || 0,
                    rate: parts[5],
                    bandwidth: parts[6],
                    mode: parts[7],
                    rsn: rsn,
                    bssid: parts[9]
                };
                if (seen[ssid] !== undefined) {
                    var e = nets[seen[ssid]];
                    if (signal > e.signal) {
                        n.inuse = e.inuse || inuse;
                        nets[seen[ssid]] = n;
                    } else if (inuse) {
                        e.inuse = true;
                    }
                    return;
                }
                seen[ssid] = nets.length;
                nets.push(n);
            });
            nets.forEach(function (n) {
                var w = wbss[String(n.bssid).toUpperCase()];
                if (w) {
                    n.dbm = w.dbm;
                    n.age = w.age;
                }
            });
            nets.sort(function (a, b) {
                if (a.inuse !== b.inuse)
                    return a.inuse ? -1 : 1;
                return b.signal - a.signal;
            });
            return nets;
        }
        onUpdated: pop.networks = value
    }

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 16
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
                margins: 10
            }
            spacing: 8

            // Header: title + rescan + on/off toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi"
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
                // Rescan
                Text {
                    visible: pop.wifiEnabled
                    text: String.fromCodePoint(0xF0450)
                    color: rescanHover.hovered ? pop.theme.accent : pop.theme.textSecondary
                    font.family: pop.theme.iconFont
                    font.pixelSize: 15
                    HoverHandler {
                        id: rescanHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: pop.det("nmcli dev wifi rescan")
                    }
                }
                // On/off toggle pill
                Rectangle {
                    width: 34
                    height: 18
                    radius: 9
                    color: pop.wifiEnabled ? pop.theme.accent : pop.theme.bgItem
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                    Rectangle {
                        width: 14
                        height: 14
                        radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: pop.wifiEnabled ? parent.width - width - 2 : 2
                        color: "white"
                        Behavior on x {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.det("nmcli radio wifi " + (pop.wifiEnabled ? "off" : "on"))
                    }
                }
            }

            // Off message
            Text {
                visible: !pop.wifiEnabled
                Layout.fillWidth: true
                text: "Wi-Fi is off"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 12
            }

            // Network list
            ListView {
                id: netList
                visible: pop.wifiEnabled
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 300)
                clip: true
                spacing: 1
                boundsBehavior: Flickable.StopAtBounds
                model: pop.networks

                // Leaving the list hides the per-AP tooltip.
                HoverHandler {
                    onHoveredChanged: if (!hovered)
                        apInfo.hide()
                }

                // Scrollbar only when the list overflows, to signal hidden items.
                readonly property bool overflowing: contentHeight > height
                ScrollBar.vertical: ScrollBar {
                    id: vbar
                    policy: netList.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    width: 6
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: vbar.pressed ? pop.theme.accent : pop.theme.bgItemHover
                        opacity: vbar.active ? 1.0 : 0.85
                    }
                    background: Rectangle {
                        color: "transparent"
                    }
                }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    radius: 6
                    color: rowHover.hovered ? pop.theme.bgItemHover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        // leave room for the scrollbar when it's shown
                        anchors.rightMargin: netList.overflowing ? 12 : 6
                        spacing: 8
                        Text {
                            text: pop.netGlyph(modelData.signal)
                            color: modelData.inuse ? pop.theme.accent : pop.theme.textSecondary
                            font.family: pop.theme.iconFont
                            font.pixelSize: 16
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.ssid
                            color: pop.theme.textPrimary
                            font.family: pop.theme.textFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: modelData.secured
                            text: String.fromCodePoint(0xF033E) // lock
                            color: pop.theme.textSecondary
                            font.family: pop.theme.iconFont
                            font.pixelSize: 12
                        }
                        Text {
                            visible: modelData.inuse
                            text: String.fromCodePoint(0xF012C) // check
                            color: pop.theme.accent
                            font.family: pop.theme.iconFont
                            font.pixelSize: 14
                        }
                    }
                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: if (hovered)
                            apInfo.showFor(modelData)
                    }
                    TapHandler {
                        onTapped: {
                            // Connects to open / already-saved networks; new
                            // secured ones get the password flow in 4c.
                            pop.det("nmcli -w 10 dev wifi connect " + pop.shellQuote(modelData.ssid));
                            pop.visible = false;
                        }
                    }
                }
            }
        }
    }
}
