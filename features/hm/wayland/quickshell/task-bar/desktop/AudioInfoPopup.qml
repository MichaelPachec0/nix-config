import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib

// Bar hover panel for audio, centered under the icon. Interactive: master volume
// slider + mute + output-device switcher chips. grabFocus:false (pointer-only),
// stays open while hovered (debounced) so the controls are usable. Mirrors
// BtInfoPopup's persistent-hover shell.
PopupWindow {
    id: tip

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var audio // Lib.AudioService

    implicitWidth: 240
    implicitHeight: Math.max(card.implicitHeight, 1)
    color: "transparent"
    visible: false
    grabFocus: false

    anchor.window: tip.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    property bool iconHovered: false
    property bool panelHovered: false
    readonly property bool keepOpen: tip.iconHovered || tip.panelHovered
    onKeepOpenChanged: tip.keepOpen ? closeTimer.stop() : closeTimer.restart()
    property Timer closeTimer: Timer {
        interval: 250
        onTriggered: tip.hide()
    }

    function show() {
        var wc = tip.anchorItem.mapToItem(null, tip.anchorItem.width / 2, 0).x;
        tip.anchor.rect.x = Math.round(wc - tip.implicitWidth / 2);
        tip.anchor.rect.y = tip.barWindow.height + 4;
        tip.anchor.rect.width = 0;
        tip.anchor.rect.height = 0;
        tip.visible = true;
    }
    function hide() {
        tip.visible = false;
    }

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: body.implicitHeight + 20
        radius: 11
        color: tip.theme.bgCard
        border.width: 1
        border.color: tip.theme.border

        HoverHandler {
            onHoveredChanged: tip.panelHovered = hovered
        }

        ColumnLayout {
            id: body
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 8

            // Title: current output device.
            Text {
                Layout.fillWidth: true
                text: (tip.audio && tip.audio.ready) ? tip.audio.deviceLabel(tip.audio.defaultSink) : "No audio"
                color: tip.theme.textPrimary
                font.family: tip.theme.textFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // Master volume + mute.
            RowLayout {
                Layout.fillWidth: true
                visible: !!tip.audio && tip.audio.ready
                spacing: 8
                Text {
                    text: tip.audio ? tip.audio.volumeGlyph(tip.audio.volume, tip.audio.muted) : ""
                    color: tip.audio && tip.audio.muted ? tip.theme.textSecondary : tip.theme.accent
                    font.family: tip.theme.iconFont
                    font.pixelSize: 16
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (tip.audio)
                            tip.audio.toggleMute()
                    }
                }
                Lib.MiniSlider {
                    id: master
                    Layout.fillWidth: true
                    theme: tip.theme
                    from: 0
                    to: 100
                    onMoved: if (tip.audio)
                        tip.audio.setVolume(v)
                    onCommitted: if (tip.audio)
                        tip.audio.setVolume(v)
                    Binding on value {
                        when: !master.dragging
                        value: tip.audio ? tip.audio.volume : 0
                    }
                }
                Text {
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignRight
                    text: tip.audio ? tip.audio.volume + "%" : ""
                    color: tip.theme.textPrimary
                    font.family: tip.theme.textFont
                    font.pixelSize: 11
                }
            }

            // Output-device chips (click to set default).
            Flow {
                Layout.fillWidth: true
                visible: !!tip.audio && tip.audio.sinks.length > 1
                spacing: 6
                Repeater {
                    model: tip.audio ? tip.audio.sinks : []
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool selected: tip.audio && tip.audio.defaultSink === chip.modelData
                        implicitHeight: 22
                        implicitWidth: chipText.implicitWidth + 18
                        radius: 11
                        color: chip.selected ? tip.theme.accent : (chipHover.hovered ? tip.theme.bgItemHover : tip.theme.bgItem)
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: tip.audio ? tip.audio.deviceLabel(chip.modelData) : ""
                            color: chip.selected ? tip.theme.textOnAccent : tip.theme.textPrimary
                            font.family: tip.theme.textFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        HoverHandler {
                            id: chipHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (tip.audio)
                                tip.audio.setDefaultSink(chip.modelData)
                        }
                    }
                }
            }
        }
    }
}
