import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib

// Audio mixer dropdown. Mirrors BluetoothPopup chrome: a grabFocus PopupWindow,
// fixed-width card, pinned-left Bottom|Right gravity. This minimal version has
// the master volume slider + mute; OUTPUT/INPUT device sections (Task 5) and the
// per-app mixer (Task 6) are added later.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var audio // Lib.AudioService

    readonly property int cardW: 280

    implicitWidth: pop.cardW
    implicitHeight: Math.max(card.implicitHeight, 1)
    color: "transparent"
    visible: false
    grabFocus: true

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function openAt(px) {
        pop.anchor.rect.x = px;
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }
    function toggle() {
        if (pop.visible) {
            pop.close();
            return;
        }
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.openAt(x - pop.cardW / 2);
    }
    function close() {
        pop.visible = false;
    }

    // Poll the per-app routing targets only while the mixer is open (for chip
    // highlighting); optimistic updates handle our own actions instantly.
    Binding {
        target: pop.audio
        property: "routeWants"
        value: pop.visible
    }

    Rectangle {
        id: card
        width: pop.cardW
        x: 0
        implicitHeight: col.implicitHeight + 20
        radius: 11
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        focus: true
        Keys.onEscapePressed: pop.close()

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 8

            // --- Header ---------------------------------------------------
            Text {
                text: "Audio"
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 13
                font.weight: Font.Bold
                Layout.fillWidth: true
            }

            Text {
                Layout.fillWidth: true
                visible: !pop.audio || !pop.audio.ready
                text: "No output devices"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 12
            }

            // --- Master volume + mute -------------------------------------
            RowLayout {
                Layout.fillWidth: true
                visible: !!pop.audio && pop.audio.ready
                spacing: 8

                Text {
                    text: pop.audio ? pop.audio.volumeGlyph(pop.audio.volume, pop.audio.muted) : ""
                    color: pop.audio && pop.audio.muted ? pop.theme.textSecondary : pop.theme.accent
                    font.family: pop.theme.iconFont
                    font.pixelSize: 16
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (pop.audio)
                            pop.audio.toggleMute()
                    }
                }
                Lib.MiniSlider {
                    id: master
                    Layout.fillWidth: true
                    theme: pop.theme
                    from: 0
                    to: 100
                    onMoved: if (pop.audio)
                        pop.audio.setVolume(v)
                    onCommitted: if (pop.audio)
                        pop.audio.setVolume(v)
                    Binding on value {
                        when: !master.dragging
                        value: pop.audio ? pop.audio.volume : 0
                    }
                }
                Text {
                    Layout.preferredWidth: 32
                    horizontalAlignment: Text.AlignRight
                    text: pop.audio ? pop.audio.volume + "%" : ""
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 11
                }
            }

            DeviceSection {
                title: "Output"
                visible: !!pop.audio && pop.audio.sinks.length > 0
                nodes: pop.audio ? pop.audio.sinks : []
                current: pop.audio ? pop.audio.defaultSink : null
                onPick: function (node) {
                    if (pop.audio)
                        pop.audio.setDefaultSink(node);
                }
            }
            DeviceSection {
                title: "Input"
                visible: !!pop.audio && pop.audio.sources.length > 0
                nodes: pop.audio ? pop.audio.sources : []
                current: pop.audio ? pop.audio.defaultSource : null
                onPick: function (node) {
                    if (pop.audio)
                        pop.audio.setDefaultSource(node);
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !!pop.audio && pop.audio.streams.length > 0
                spacing: 4
                Text {
                    text: "Apps"
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                Repeater {
                    model: pop.audio ? pop.audio.streams : []
                    AppRow {
                        required property var modelData
                        stream: modelData
                    }
                }
            }
        }
    }

    // A titled list of selectable device rows; the current default gets a dot.
    component DeviceSection: ColumnLayout {
        id: sec
        property string title: ""
        property var nodes: []
        property var current: null
        signal pick(var node)
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: sec.title
            color: pop.theme.textSecondary
            font.family: pop.theme.textFont
            font.pixelSize: 10
            font.weight: Font.Bold
        }
        Repeater {
            model: sec.nodes
            Rectangle {
                id: drow
                required property var modelData
                readonly property bool isCurrent: sec.current === drow.modelData
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 6
                color: rowHover.hovered ? pop.theme.bgItemHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 10
                    spacing: 8
                    Text {
                        text: pop.audio ? pop.audio.typeGlyph(drow.modelData) : ""
                        color: drow.isCurrent ? pop.theme.accent : pop.theme.textSecondary
                        font.family: pop.theme.iconFont
                        font.pixelSize: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: pop.audio ? pop.audio.deviceLabel(drow.modelData) : ""
                        color: pop.theme.textPrimary
                        font.family: pop.theme.textFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: drow.isCurrent
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: pop.theme.accent
                    }
                }
                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: sec.pick(drow.modelData)
                }
            }
        }
    }

    // One per-app stream: icon + name + volume slider + mute + route chevron.
    component AppRow: ColumnLayout {
        id: arow
        required property var stream
        property bool routeOpen: false
        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Image {
                Layout.alignment: Qt.AlignVCenter
                source: pop.audio ? pop.audio.appIcon(arow.stream) : ""
                visible: source != ""
                sourceSize.width: 32
                sourceSize.height: 32
                width: 16
                height: 16
                fillMode: Image.PreserveAspectFit
            }
            Text {
                Layout.preferredWidth: 70
                text: pop.audio ? pop.audio.appName(arow.stream) : ""
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Lib.MiniSlider {
                id: appVol
                Layout.fillWidth: true
                theme: pop.theme
                from: 0
                to: 100
                onMoved: if (arow.stream && arow.stream.audio)
                    arow.stream.audio.volume = v / 100
                onCommitted: if (arow.stream && arow.stream.audio)
                    arow.stream.audio.volume = v / 100
                Binding on value {
                    when: !appVol.dragging
                    value: (arow.stream && arow.stream.audio) ? Math.round(arow.stream.audio.volume * 100) : 0
                }
            }
            // Mute pill.
            Text {
                text: (arow.stream && arow.stream.audio && arow.stream.audio.muted) ? String.fromCodePoint(0xF0581) : String.fromCodePoint(0xF057E)
                color: (arow.stream && arow.stream.audio && arow.stream.audio.muted) ? pop.theme.textSecondary : pop.theme.textPrimary
                font.family: pop.theme.iconFont
                font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (arow.stream && arow.stream.audio)
                        arow.stream.audio.muted = !arow.stream.audio.muted
                }
            }
            // Route chevron: toggles the inline device list.
            Text {
                visible: pop.audio && pop.audio.sinks.length > 1
                text: String.fromCodePoint(arow.routeOpen ? 0xF0143 : 0xF0140) // chevron up/down
                color: pop.theme.textSecondary
                font.family: pop.theme.iconFont
                font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: arow.routeOpen = !arow.routeOpen
                }
            }
        }
        // Inline route targets: "Auto" (follow global default) + each sink.
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            visible: arow.routeOpen
            spacing: 6
            // "Auto": clear the stream's target so it follows the default sink.
            Rectangle {
                id: autoChip
                readonly property bool selected: pop.audio && pop.audio.streamEndpoint(arow.stream) === "auto"
                implicitHeight: 20
                implicitWidth: autoText.implicitWidth + 16
                radius: 10
                color: autoChip.selected ? pop.theme.accent : (autoHover.hovered ? pop.theme.bgItemHover : pop.theme.bgItem)
                Text {
                    id: autoText
                    anchors.centerIn: parent
                    text: "Auto"
                    color: autoChip.selected ? pop.theme.textOnAccent : pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                }
                HoverHandler {
                    id: autoHover
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (pop.audio)
                            pop.audio.routeStreamAuto(arow.stream);
                        arow.routeOpen = false;
                    }
                }
            }
            Repeater {
                model: pop.audio ? pop.audio.sinks : []
                Rectangle {
                    id: tchip
                    required property var modelData
                    readonly property bool selected: pop.audio && pop.audio.streamEndpoint(arow.stream) === String(tchip.modelData.name)
                    implicitHeight: 20
                    implicitWidth: tchipText.implicitWidth + 16
                    radius: 10
                    color: tchip.selected ? pop.theme.accent : (tchipHover.hovered ? pop.theme.bgItemHover : pop.theme.bgItem)
                    Text {
                        id: tchipText
                        anchors.centerIn: parent
                        text: pop.audio ? pop.audio.deviceLabel(tchip.modelData) : ""
                        color: tchip.selected ? pop.theme.textOnAccent : pop.theme.textPrimary
                        font.family: pop.theme.textFont
                        font.pixelSize: 10
                    }
                    HoverHandler {
                        id: tchipHover
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (pop.audio)
                                pop.audio.routeStream(arow.stream, tchip.modelData);
                            arow.routeOpen = false;
                        }
                    }
                }
            }
        }
    }
}
