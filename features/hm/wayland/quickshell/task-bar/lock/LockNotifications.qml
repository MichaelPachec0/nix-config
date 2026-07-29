// features/hm/wayland/quickshell/task-bar/lock/LockNotifications.qml
// Lock-native notification list. Reads notifSvc.groups, classifies each via
// `policy`, renders theme-styled cards. Task 3: sensitive shape only (app icon +
// app name + summary; NO body/image/actions). Tiers/actions land in Task 4, cap
// + hideAll in Task 5. See docs/lock-notifications/spec.md.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

ColumnLayout {
    id: root
    property var notifications: null   // Lib.NotifService
    property var policy: null          // LockNotifyPolicy
    property var theme: null           // live ThemeEngine
    property real contentOpacity: 1.0
    property int maxCards: 4
    property bool hideAll: false

    readonly property var groups: (root.notifications && LockConfig.notifEnable) ? root.notifications.groups : []
    spacing: 8
    opacity: root.contentOpacity
    visible: root.groups.length > 0

    Repeater {
        model: root.groups
        delegate: ColumnLayout {
            required property var modelData // {app, list}
            Layout.alignment: Qt.AlignRight
            spacing: 4
            // app header
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 6
                Image {
                    source: (modelData.list[0] && modelData.list[0].appIcon) ? modelData.list[0].appIcon : ""
                    sourceSize.width: 16; sourceSize.height: 16
                    visible: source != ""
                }
                LockText {
                    text: (modelData.app || "Notifications") + "  " + modelData.list.length
                    color: root.theme ? root.theme.textSecondary : "#a89984"
                    font.pixelSize: 12; font.bold: true
                }
            }
            Repeater {
                model: modelData.list
                delegate: Rectangle {
                    required property var modelData // Notification
                    readonly property var cls: root.policy ? root.policy.classify(modelData, root.hideAll) : ({visibility: "sensitive", interactive: false})
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredWidth: 260
                    implicitHeight: cardCol.implicitHeight + 12
                    radius: 8
                    color: root.theme ? root.theme.bgCard : "#282828"
                    opacity: 0.9
                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        LockText {
                            Layout.fillWidth: true
                            text: modelData.summary || (modelData.appName || "Notification")
                            color: root.theme ? root.theme.textPrimary : "#ebdbb2"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
