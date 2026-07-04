import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../lib" as Lib

// Quick-settings card (Phase 2d, step 3): a left column of toggles (WiFi /
// Bluetooth / DND) and two vertical sliders (brightness via brightnessctl,
// volume via the native PipeWire sink). State polls run only while the hub is
// open (active). DND drives the Quickshell-native notification service
// (NotifService.dnd), which suppresses toast popups.
Lib.Card {
    id: root

    property bool active: true
    property var notif: null // Lib.NotifService (for the DND toggle)
    signal closeRequested

    // Keep the default sink tracked so its audio.volume/muted stay live.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // --- State polls -------------------------------------------------------
    Lib.CommandPoll {
        id: briPoll
        interval: 1500
        running: root.active
        command: ["bash", "-lc", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '% ' || true"]
        parse: function (o) {
            var n = Number(String(o).trim());
            return isFinite(n) ? n : 50;
        }
        onUpdated: if (!briS.pressed)
            briS.value = value
    }
    Lib.CommandPoll {
        id: wifiOn
        interval: 2500
        running: root.active
        command: ["bash", "-lc", "nmcli -t -f WIFI g 2>/dev/null | head -n1 || true"]
        parse: function (o) {
            return String(o).trim() === "enabled";
        }
    }
    Lib.CommandPoll {
        id: wifiSSID
        interval: 5000
        running: root.active
        command: ["bash", "-lc", "nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2; exit}' || true"]
        parse: function (o) {
            var s = String(o).trim() || "WiFi";
            return s.length > 10 ? s.slice(0, 10) : s;
        }
    }
    Lib.CommandPoll {
        id: btOn
        interval: 3000
        running: root.active
        command: ["bash", "-lc", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        parse: function (o) {
            return String(o).trim() === "on";
        }
    }
    function det(cmd) {
        Quickshell.execDetached(["bash", "-lc", cmd]);
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        spacing: 12

        // LEFT: toggle column
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 8

            Lib.ExpressiveButton {
                Layout.fillHeight: true
                theme: root.theme
                icon: wifiOn.value ? String.fromCodePoint(0xF05A9) // wifi
                 : String.fromCodePoint(0xF05AA) // wifi-off
                label: String(wifiSSID.value || "WiFi")
                active: Boolean(wifiOn.value)
                onClicked: root.det("nmcli radio wifi " + (wifiOn.value ? "off" : "on"))
                onRightClicked: {
                    root.closeRequested();
                    root.det("nm-connection-editor >/dev/null 2>&1 &");
                }
            }
            Lib.ExpressiveButton {
                Layout.fillHeight: true
                theme: root.theme
                icon: btOn.value ? String.fromCodePoint(0xF00AF) // bluetooth
                 : String.fromCodePoint(0xF00B2) // bluetooth-off
                label: btOn.value ? "On" : "Off"
                active: Boolean(btOn.value)
                onClicked: root.det("bluetoothctl power " + (btOn.value ? "off" : "on"))
                onRightClicked: {
                    root.closeRequested();
                    root.det("blueman-manager >/dev/null 2>&1 &");
                }
            }
            Lib.ExpressiveButton {
                Layout.fillHeight: true
                theme: root.theme
                icon: (root.notif && root.notif.dnd) ? String.fromCodePoint(0xF09A6) // bell-sleep
                 : String.fromCodePoint(0xF009A) // bell
                label: (root.notif && root.notif.dnd) ? "Silent" : "Notify"
                active: Boolean(root.notif && root.notif.dnd)
                onClicked: if (root.notif)
                    root.notif.dnd = !root.notif.dnd
            }
        }

        // RIGHT: the two sliders.
        RowLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 12

            // Brightness
            Lib.ExpressiveSlider {
                id: briS
                Layout.fillHeight: true
                Layout.fillWidth: true
                theme: root.theme
                orientation: Qt.Vertical
                icon: String.fromCharCode(0xF185) // sun
                from: 0
                to: 100
                value: 50
                onUserChanged: v => root.det("brightnessctl set " + Math.round(v) + "%")
            }

            // Volume (native PipeWire default sink)
            Lib.ExpressiveSlider {
                id: volS
                Layout.fillHeight: true
                Layout.fillWidth: true
                theme: root.theme
                orientation: Qt.Vertical
                readonly property var sink: Pipewire.defaultAudioSink
                readonly property real sinkVol: (sink && sink.audio) ? sink.audio.volume * 100 : 0
                onSinkVolChanged: if (!pressed)
                    value = Math.round(sinkVol)
                Component.onCompleted: value = Math.round(sinkVol)
                icon: (sink && sink.audio && sink.audio.muted) ? String.fromCharCode(0xF026) // muted
                 : String.fromCharCode(0xF028) // volume
                from: 0
                to: 100
                onUserChanged: v => {
                    if (sink && sink.audio)
                        sink.audio.volume = v / 100;
                }
            }
        }
    }
}
