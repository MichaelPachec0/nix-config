import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../lib" as Lib

// Quick-settings card (Phase 2d, step 3). 3a: the two vertical sliders --
// brightness (brightnessctl) and volume (native PipeWire sink). The toggle
// column (WiFi / Bluetooth / DND) lands in 3b where the placeholder is.
Lib.Card {
    id: root

    // Keep the default sink tracked so its audio.volume/muted stay live.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // Brightness has no native Quickshell service -> poll brightnessctl.
    Lib.CommandPoll {
        id: briPoll
        interval: 1500
        command: ["bash", "-lc", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '% ' || true"]
        parse: function (o) {
            var n = Number(String(o).trim());
            return isFinite(n) ? n : 50;
        }
        onUpdated: if (!briS.pressed)
            briS.value = value
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        spacing: 12

        // LEFT: toggle column lands here in 3b.
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            radius: root.theme.radiusInner
            color: root.theme.bgItem
            Text {
                anchors.centerIn: parent
                text: "toggles (3b)"
                color: root.theme.textSecondary
                font.family: root.theme.textFont
                font.pixelSize: 12
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
                onUserChanged: v => Quickshell.execDetached(["bash", "-lc", "brightnessctl set " + Math.round(v) + "%"])
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
                // Sync from the sink only when the user isn't dragging.
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
