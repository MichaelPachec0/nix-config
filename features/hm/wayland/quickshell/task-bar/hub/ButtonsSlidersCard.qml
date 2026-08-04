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
    property var net: null // shared Lib.NetworkService, hoisted to ShellRoot
    signal closeRequested

    readonly property string _libDir: Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib"

    // Radio + SSID come off the shared NetworkService rather than two polls of
    // this card's own. Those polls ran wifi-enabled.sh (2.5s) and
    // wifi-active-ssid.sh (5s) -- both re-asking nmcli for state net-status.sh
    // already reports every 4s for the bar. Reading it here also means the
    // toggle is correct the instant the hub opens, instead of after its first
    // tick. Named wifiEnabled/wifiLabel, NOT wifiOn/wifiSSID: an own property
    // sharing a name with an enclosing id resolves to the property and silently
    // self-references.
    readonly property bool wifiEnabled: Boolean(root.net && root.net.wifiRadio)
    readonly property string wifiLabel: {
        var s = (root.net && root.net.ssid) ? String(root.net.ssid) : "";
        if (s === "")
            return "WiFi";
        return s.length > 10 ? s.slice(0, 10) : s;
    }

    // `nmcli radio wifi` is fire-and-forget, and NetworkService's own tick is
    // 4s -- slower than the 2.5s poll this card used to run, so the switch would
    // have felt laggier after the change. Re-poll once shortly after the toggle
    // instead. Deliberately NOT an optimistic local flip plus an immediate
    // re-poll: execDetached has not even reached NetworkManager by the time a
    // poll started in the same frame reads status back, so the confirming read
    // returns the OLD value and the switch visibly snaps back before settling.
    property Timer radioSettle: Timer {
        interval: 600
        repeat: false
        onTriggered: if (root.net)
            root.net.refresh()
    }

    // Keep the default sink tracked so its audio.volume/muted stay live.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // --- State polls -------------------------------------------------------
    Lib.CommandPoll {
        id: briPoll
        interval: 1500
        running: root.active
        command: [root._libDir + "/brightness-get.sh"]
        parse: function (o) {
            var n = Number(String(o).trim());
            return isFinite(n) ? n : 50;
        }
        onUpdated: if (!briS.pressed)
            briS.value = value
    }
    Lib.CommandPoll {
        id: btOn
        interval: 3000
        running: root.active
        command: [root._libDir + "/bt-powered.sh"]
        parse: function (o) {
            return String(o).trim() === "on";
        }
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
                icon: root.wifiEnabled ? String.fromCodePoint(0xF05A9) // wifi
                 : String.fromCodePoint(0xF05AA) // wifi-off
                label: root.wifiLabel
                active: root.wifiEnabled
                onClicked: {
                    Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]);
                    root.radioSettle.restart();
                }
                onRightClicked: {
                    root.closeRequested();
                    Quickshell.execDetached(["nm-connection-editor"]);
                }
            }
            Lib.ExpressiveButton {
                Layout.fillHeight: true
                theme: root.theme
                icon: btOn.value ? String.fromCodePoint(0xF00AF) // bluetooth
                 : String.fromCodePoint(0xF00B2) // bluetooth-off
                label: btOn.value ? "On" : "Off"
                active: Boolean(btOn.value)
                onClicked: Quickshell.execDetached(["bluetoothctl", "power", btOn.value ? "off" : "on"])
                onRightClicked: {
                    root.closeRequested();
                    Quickshell.execDetached(["blueman-manager"]);
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
                onUserChanged: v => Quickshell.execDetached(["brightnessctl", "set", Math.round(v) + "%"])
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
