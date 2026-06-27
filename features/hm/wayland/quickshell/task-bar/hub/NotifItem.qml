import QtQuick
import QtQuick.Layouts
import Quickshell

// One notification row in the hub NotificationsCard / toast overlay. A rich
// renderer: shows the app-set image (album art, avatar, screenshot) or the
// resolved app icon -- falling back to a bell glyph -- plus summary, body and
// the app's action buttons. Click fires the "default" action if the app set
// one, otherwise dismisses. Adapted from surface-dots (Gruvbox theme tokens).
Rectangle {
    id: root

    required property QtObject theme
    required property string app
    required property string summary
    required property string body
    property bool critical: false
    // The backing Notification object (Quickshell.Services.Notifications). Optional
    // so plain-string callers still work; supplies image/appIcon/actions when set.
    property var source: null
    // compact: single-line height with body + buttons hidden (used in a collapsed
    // stack). interactive: when false the card ignores clicks (peeking cards in a
    // stack -- the click falls through to the stack's expand catcher).
    property bool compact: false
    property bool interactive: true

    signal dismissRequested

    // --- Rich data derived from the backing Notification --------------------
    // App-set image: already a usable URL (image:// provider for raw D-Bus
    // pixels, or a file/icon URL for image-path). Empty when none was sent.
    readonly property string imageUrl: (root.source && root.source.image) ? String(root.source.image) : ""
    // App icon resolved to a path. Pass through real paths; resolve names.
    readonly property string appIconUrl: {
        if (!root.source || !root.source.appIcon)
            return "";
        var a = String(root.source.appIcon);
        if (a.startsWith("/") || a.startsWith("file:") || a.startsWith("image:"))
            return a;
        return Quickshell.iconPath(a, "");
    }
    readonly property var actions: root.source ? root.source.actions : []
    // The conventional click-the-body action; not shown as a button.
    readonly property var defaultAction: {
        for (var i = 0; i < root.actions.length; i++)
            if (root.actions[i].identifier === "default")
                return root.actions[i];
        return null;
    }
    // Real buttons: everything except "default" that has a label.
    readonly property var buttonActions: {
        var out = [];
        for (var i = 0; i < root.actions.length; i++) {
            var a = root.actions[i];
            if (a.identifier !== "default" && String(a.text).length > 0)
                out.push(a);
        }
        return out;
    }
    readonly property bool hasImage: root.imageUrl !== "" || root.appIconUrl !== ""
    // Inline reply: the app sent an "inline-reply" action. The placeholder is
    // that action's label. sendInlineReply() also closes the notification unless
    // the app marked it resident, so no separate dismiss is needed.
    readonly property bool hasReply: root.source ? root.source.hasInlineReply === true : false
    readonly property string replyPlaceholder: (root.source && String(root.source.inlineReplyPlaceholder).length > 0) ? String(root.source.inlineReplyPlaceholder) : "Reply..."

    function sendReply() {
        var t = String(replyField.text).trim();
        if (t.length === 0 || !root.source)
            return;
        root.source.sendInlineReply(t);
        replyField.text = "";
    }

    implicitHeight: root.compact ? 50 : (contentRow.implicitHeight + 22)
    radius: 12
    color: hover.hovered ? root.theme.bgItemHover : root.theme.bgItem
    Behavior on color {
        ColorAnimation {
            duration: 140
        }
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        // A "default" action means click = activate (which also dismisses);
        // otherwise click just dismisses, as before.
        onClicked: {
            if (root.defaultAction)
                root.defaultAction.invoke();
            else
                root.dismissRequested();
        }
    }

    RowLayout {
        id: contentRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 11
            rightMargin: 11
        }
        spacing: 10

        // Leading visual: app image (square) > app icon (square) > bell badge.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            // Big square for a real image; small badge for an icon/glyph.
            readonly property int slot: root.imageUrl !== "" ? (root.compact ? 30 : 40) : 28
            width: slot
            height: slot
            radius: root.hasImage ? 8 : 999
            clip: true
            color: {
                if (root.hasImage)
                    return root.theme.bgItem;
                return root.critical ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.16) : root.theme.subtleFill;
            }

            // Bell fallback, shown when there's no usable image/icon.
            Text {
                anchors.centerIn: parent
                visible: !root.hasImage || pic.status !== Image.Ready
                text: String.fromCodePoint(0xF009A) // mdi bell
                font.family: root.theme.iconFont
                font.pixelSize: 14
                color: root.critical ? root.theme.accentRed : root.theme.accent
            }
            Image {
                id: pic
                anchors.fill: parent
                // Slight inset for app icons so logos aren't edge-to-edge.
                anchors.margins: (root.imageUrl === "" && root.appIconUrl !== "") ? 4 : 0
                visible: root.hasImage && pic.status === Image.Ready
                source: root.imageUrl !== "" ? root.imageUrl : root.appIconUrl
                // Crop a photo to fill; fit an icon so it isn't clipped.
                fillMode: root.imageUrl !== "" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize.width: 80
                sourceSize.height: 80
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: String(root.app).toUpperCase().replace(/\n/g, ' ')
                font.family: root.theme.textFont
                font.pixelSize: 9
                font.weight: Font.Bold
                color: root.critical ? root.theme.accentRed : root.theme.textSecondary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.summary.replace(/\n/g, ' ')
                font.family: root.theme.textFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: root.theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: !root.compact && root.body !== ""
                text: root.body.replace(/\n/g, ' ')
                font.family: root.theme.textFont
                font.pixelSize: 11
                color: root.theme.textSecondary
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            // Action buttons (full cards only). Each fires its action; invoke()
            // dismisses the notification unless the app marked it resident.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !root.compact && root.buttonActions.length > 0
                spacing: 6
                Repeater {
                    model: root.buttonActions
                    delegate: Rectangle {
                        id: actBtn
                        required property var modelData
                        implicitHeight: 26
                        implicitWidth: actLabel.implicitWidth + 22
                        radius: 8
                        color: actHover.hovered ? root.theme.bgItemHover : root.theme.bgItem
                        border.width: 1
                        border.color: root.theme.border
                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }
                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: actBtn.modelData.text.replace(/\n/g, ' ')
                            color: root.theme.textPrimary
                            font.family: root.theme.textFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        HoverHandler {
                            id: actHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: actBtn.modelData.invoke()
                        }
                    }
                }
            }

            // Inline reply field (full cards only). Typeable wherever the surface
            // holds keyboard focus -- the hub always; toasts when clicked (their
            // layer takes focus on demand). Enter or the send button replies.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !root.compact && root.hasReply
                implicitHeight: 32
                radius: 8
                color: root.theme.bgItem
                border.width: 1
                border.color: replyField.activeFocus ? root.theme.accent : root.theme.border
                Behavior on border.color {
                    ColorAnimation {
                        duration: 140
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 4

                    TextInput {
                        id: replyField
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.textPrimary
                        font.family: root.theme.textFont
                        font.pixelSize: 11
                        clip: true
                        selectByMouse: true
                        selectionColor: root.theme.accent
                        onAccepted: root.sendReply()

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: replyField.width
                            visible: replyField.text.length === 0
                            text: root.replyPlaceholder
                            color: root.theme.textSecondary
                            font: replyField.font
                            elide: Text.ElideRight
                        }
                    }

                    // Send (paper-plane); dim until there's text to send.
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 7
                        color: (sendHover.hovered && replyField.text.length > 0) ? root.theme.bgItemHover : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF048A) // mdi send
                            font.family: root.theme.iconFont
                            font.pixelSize: 14
                            color: replyField.text.length > 0 ? root.theme.accent : root.theme.textSecondary
                        }
                        HoverHandler {
                            id: sendHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: replyField.text.length > 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.sendReply()
                        }
                    }
                }
            }
        }
    }
}
