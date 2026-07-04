import QtQuick
import QtQuick.Layouts
import "../lib" as Lib

// Hub inline power menu (Phase 2d, step 4): an uptime line + a 3-column grid of
// power actions. Presentation only -- emits actionRequested(action); the Header
// maps the action to a shell command. Gruvbox-dark only (the surface-dots
// light/dark tint mixing + ClickRipple are dropped for v1). Reboot/Shutdown are
// styled danger-red. Mouse-driven; keyboard nav is a later add.
Item {
    id: root

    required property QtObject theme
    property bool active: false // gates the uptime poll

    signal actionRequested(string action)

    implicitHeight: layout.implicitHeight

    // glyph = Nerd Font codepoint (rendered via fromCodePoint, BMP + astral MDI).
    readonly property var actions: [
        {
            label: "Lock",
            glyph: 0xF023,
            cmd: "lock",
            danger: false
        },
        {
            label: "Suspend",
            glyph: 0xF186,
            cmd: "suspend",
            danger: false
        },
        {
            label: "Logout",
            glyph: 0xF08B,
            cmd: "logout",
            danger: false
        },
        {
            label: "Hibernate",
            glyph: 0xF0717,
            cmd: "hibernate",
            danger: false
        },
        {
            label: "Reboot",
            glyph: 0xF021,
            cmd: "reboot",
            danger: true
        },
        {
            label: "Shutdown",
            glyph: 0xF011,
            cmd: "shutdown",
            danger: true
        }
    ]

    property string uptimeStr: ""
    Lib.CommandPoll {
        interval: 60000
        running: root.active
        command: ["bash", "-lc", "uptime -p | sed -e 's/^up //'"]
        parse: function (o) {
            return String(o).trim();
        }
        onUpdated: root.uptimeStr = value
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: 8

        // Uptime line
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            Text {
                text: String.fromCodePoint(0xF017) // clock
                color: root.theme.textSecondary
                font.family: root.theme.iconFont
                font.pixelSize: 11
            }
            Text {
                text: "Uptime " + (root.uptimeStr || "...")
                color: root.theme.textSecondary
                font.family: root.theme.textFont
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: root.actions
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: 12
                    color: root.theme.subtleFill

                    readonly property color accentFor: modelData.danger ? root.theme.accentRed : root.theme.accent

                    // Hover wash in the action's accent.
                    Rectangle {
                        anchors.fill: parent
                        radius: btn.radius
                        color: btn.accentFor
                        opacity: btnHover.hovered ? 0.16 : 0.0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    border.width: btnHover.hovered ? 1 : 0
                    border.color: Qt.rgba(btn.accentFor.r, btn.accentFor.g, btn.accentFor.b, 0.6)

                    scale: btnTap.pressed ? 0.97 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }

                    HoverHandler {
                        id: btnHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        id: btnTap
                        onTapped: root.actionRequested(btn.modelData.cmd)
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 3
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: String.fromCodePoint(btn.modelData.glyph)
                            font.family: root.theme.iconFont
                            font.pixelSize: 19
                            color: btnHover.hovered ? btn.accentFor : root.theme.textPrimary
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: btn.modelData.label
                            font.family: root.theme.textFont
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: btnHover.hovered ? root.theme.textPrimary : root.theme.textSecondary
                        }
                    }
                }
            }
        }
    }
}
