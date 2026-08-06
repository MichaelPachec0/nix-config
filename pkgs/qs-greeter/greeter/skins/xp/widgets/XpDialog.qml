import QtQuick
// Quickshell's qmlscanner only resolves ONE bare same-directory type per
// document reliably (confirmed empirically: a second bare sibling
// reference in the same file intermittently reports "is not a type" even
// though the first one resolved fine, whichever type happened to be
// scanned first). An explicit `import "." as Kit` sidesteps it entirely,
// so both XpBanner and XpButton below are referenced as Kit.<Type> rather
// than relying on the implicit same-directory lookup.
import "." as Kit

Item {
    id: root
    required property var theme
    property string bannerTitle: ""
    property string bannerSubtitle: ""
    property Item contentItem: null
    property var buttons: []

    implicitWidth: 420
    implicitHeight: theme.bannerHeight + contentArea.implicitHeight
        + buttonArea.height
    width: implicitWidth
    height: implicitHeight

    // Drop shadow: sits behind the face, offset via negative margins so it
    // reads as a soft frame shadow rather than a border.
    Rectangle {
        anchors.fill: face
        anchors.margins: -4
        radius: theme.radius + 2
        color: theme.faceDark
        opacity: 0.25
        z: -1
    }

    Rectangle {
        id: face
        anchors.fill: parent
        color: theme.face
        radius: theme.radius
        border.width: 1
        border.color: theme.faceDark

        // Raised outer edge: a light inset border one pixel inside the true
        // frame, the same etched-chrome idea XpTextField uses for its
        // sunken field, mirrored here to read as raised instead of sunken.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, theme.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: theme.faceLight
        }

        Column {
            id: layout
            anchors.fill: parent
            anchors.margins: theme.bevel
            spacing: 0

            Kit.XpBanner {
                id: banner
                theme: root.theme
                title: root.bannerTitle
                subtitle: root.bannerSubtitle
                width: layout.width
            }

            Item {
                id: contentArea
                width: layout.width
                height: implicitHeight
                implicitHeight: root.contentItem
                    ? root.contentItem.implicitHeight + theme.dialogPad * 2
                    : theme.dialogPad * 2
            }

            // A plain Item, not a positioner, so the Row inside it is free
            // to anchor itself to the right edge with a margin -- anchoring
            // a Row itself (as opposed to anchoring a Row's *children*,
            // which QtQuick explicitly forbids and warns about) is fine.
            Item {
                id: buttonArea
                width: layout.width
                height: theme.controlHeight + 2 + theme.dialogPad

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: theme.dialogPad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: theme.rowSpacing

                    Repeater {
                        model: root.buttons
                        delegate: Kit.XpButton {
                            // XpButton declares `required property var theme`,
                            // which switches Qt6's delegate model into
                            // required-property injection mode: it then
                            // stops auto-exposing `modelData` as an inherited
                            // context property unless the delegate ALSO
                            // declares it required (confirmed empirically --
                            // omitting this line throws "modelData is not
                            // defined" for every property binding below).
                            required property var modelData
                            theme: root.theme
                            text: modelData.text || ""
                            isDefault: !!modelData.isDefault
                            enabled: modelData.enabled === undefined ? true : modelData.enabled
                            onClicked: if (modelData.onClicked) modelData.onClicked()
                        }
                    }
                }
            }
        }
    }

    // Reparents the caller-supplied content Item into contentArea and pins
    // it there. Widgets stay dumb: XpDialog does not know what contentItem
    // is, only that it is an Item it can anchor.fill into its content slot.
    function _layoutContent() {
        if (!root.contentItem) return;
        root.contentItem.parent = contentArea;
        root.contentItem.anchors.fill = contentArea;
        root.contentItem.anchors.margins = theme.dialogPad;
    }
    Component.onCompleted: root._layoutContent()
    onContentItemChanged: root._layoutContent()
}
