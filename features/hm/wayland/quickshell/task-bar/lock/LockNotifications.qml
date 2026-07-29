// features/hm/wayland/quickshell/task-bar/lock/LockNotifications.qml
// Lock-native notification list. Reads notifSvc.groups, classifies each via
// `policy`, renders theme-styled cards. Task 4: full/sensitive/hidden tier
// rendering + trusted-tier action buttons. cap + hideAll land in Task 5. See
// docs/lock-notifications/spec.md.
//
// PRIVACY: this renders on a LOCKED, unauthenticated screen. `modelData.body`
// and `modelData.image` must be referenced ONLY inside a `_vis === "full"`
// -gated ternary so the string is never even read below the full tier.
// `modelData.summary` must be referenced ONLY inside a `_vis !== "hidden"`
// -gated ternary, for the same reason. Do not "fix" this by adding a
// `visible:` guard around an unconditional `text: modelData.body` (or
// `.summary`) -- a hidden Text item still holds the string.
import QtQuick
import QtQuick.Layouts
import Quickshell

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

    // Strip markup from a notification body (bodies may carry a small HTML
    // subset per the notification spec). Full-tier only -- see PRIVACY note.
    function _plain(s) { return s ? String(s).replace(/<[^>]*>/g, "").trim() : ""; }

    // Icon/image resolution: a real path / file: / image: URL passes through
    // as-is; a bare icon NAME must be resolved via Quickshell.iconPath or it
    // silently fails to load. Mirrors hub/NotifItem.qml's appIconUrl/imageUrl.
    function _resolveIconLike(v) {
        if (!v)
            return "";
        var s = String(v);
        if (s.startsWith("/") || s.startsWith("file:") || s.startsWith("image:"))
            return s;
        return Quickshell.iconPath(s, "");
    }
    function _iconUrl(appIcon) { return root._resolveIconLike(appIcon); }
    function _imageUrl(image) { return root._resolveIconLike(image); }

    // Count of hidden-tier notifications in a group's list (private tier, or
    // hideAll). Used for the group's "N hidden" line -- counts only, no
    // summary/body/image of a hidden notification is ever touched.
    function _hiddenCount(list) {
        if (!root.policy)
            return 0;
        var c = 0;
        for (var i = 0; i < list.length; i++)
            if (root.policy.classify(list[i], root.hideAll).visibility === "hidden")
                c++;
        return c;
    }

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
                    source: (modelData.list[0] && modelData.list[0].appIcon) ? root._iconUrl(modelData.list[0].appIcon) : ""
                    sourceSize.width: 16; sourceSize.height: 16
                    visible: source != ""
                }
                LockText {
                    text: (modelData.app || "Notifications") + "  " + modelData.list.length
                    color: root.theme ? root.theme.textSecondary : "#a89984"
                    font.pixelSize: 12; font.bold: true
                }
            }
            // hidden-tier count line (private tier / hideAll): count only --
            // no summary/body/image of a hidden notification is ever read.
            LockText {
                Layout.alignment: Qt.AlignRight
                visible: root._hiddenCount(modelData.list) > 0
                text: root._hiddenCount(modelData.list) + " hidden"
                color: root.theme ? root.theme.textSecondary : "#a89984"
                font.pixelSize: 11; opacity: 0.8
            }
            Repeater {
                model: modelData.list
                delegate: Rectangle {
                    id: cardRect
                    required property var modelData // Notification
                    readonly property var cls: root.policy ? root.policy.classify(modelData, root.hideAll) : ({visibility: "sensitive", interactive: false})
                    // HIDDEN tier: the card does not render at all. QtQuick.Layouts
                    // excludes invisible items from layout, so this collapses to
                    // zero size; the group's "N hidden" line above covers it.
                    visible: cardRect.cls.visibility !== "hidden"
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
                        spacing: 3
                        // resolved policy for this card, computed once
                        readonly property string _vis: cardRect.cls.visibility
                        readonly property bool _interactive: cardRect.cls.interactive

                        // summary line (sensitive AND full). `modelData.summary` is
                        // referenced ONLY inside this hidden-gated ternary -- a
                        // visible:false Text would still hold the string in the
                        // render tree, which is exactly the leak the file-header
                        // PRIVACY note forbids for body/image. See PRIVACY note.
                        LockText {
                            Layout.fillWidth: true
                            text: cardCol._vis !== "hidden" ? (modelData.summary || (modelData.appName || "Notification")) : ""
                            color: root.theme ? root.theme.textPrimary : "#ebdbb2"
                            font.pixelSize: 13; elide: Text.ElideRight
                        }
                        // BODY: full tier only. `modelData.body` is referenced ONLY
                        // inside this full-gated ternary -- see file-header PRIVACY note.
                        LockText {
                            Layout.fillWidth: true
                            visible: cardCol._vis === "full" && text.length > 0
                            text: cardCol._vis === "full" ? root._plain(modelData.body) : ""
                            color: root.theme ? root.theme.textSecondary : "#a89984"
                            font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                        }
                        // IMAGE THUMB: full tier only. `modelData.image` is referenced
                        // ONLY inside this full-gated ternary -- see PRIVACY note.
                        Image {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            Layout.alignment: Qt.AlignLeft
                            visible: cardCol._vis === "full" && source != ""
                            source: cardCol._vis === "full" ? root._imageUrl(modelData.image) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 128; sourceSize.height: 128
                        }
                        // ACTIONS: trusted tier only (cls.interactive). invoke()
                        // dials straight into the notification bus -- NO PAM gate.
                        RowLayout {
                            visible: cardCol._interactive
                            spacing: 6
                            Repeater {
                                model: cardCol._interactive ? modelData.actions : []
                                delegate: Rectangle {
                                    required property var modelData // NotificationAction
                                    radius: 6; color: root.theme ? root.theme.accent : "#87b158"
                                    implicitWidth: aLabel.implicitWidth + 16; implicitHeight: aLabel.implicitHeight + 8
                                    LockText {
                                        id: aLabel; anchors.centerIn: parent
                                        text: modelData.text; color: root.theme ? root.theme.textOnAccent : "#1d2021"
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.invoke()   // trusted-tier only; no PAM
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
