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
    // Brand-panel content, all empty by default -- see XpBanner's own note
    // on why this skin ships no default copyright or vendor string.
    property bool bannerBrand: false
    property string bannerCopyright: ""
    property string bannerEdition: ""
    property string bannerWordmark: ""
    property string bannerWordmarkAccent: ""
    property string bannerVendor: ""
    property string bannerImage: ""
    property var buttons: []

    // The real dialog is a wide, short box -- its two field rows sit on
    // single lines with their labels beside them, so it has no reason to be
    // tall. A narrower box forces the fields to look cramped next to their
    // label column.
    //
    // When the banner is carrying artwork, the dialog takes ITS width
    // instead, so the bitmap renders 1:1. That panel is almost entirely
    // logotype, and rescaling type inside a bitmap softens it visibly --
    // which is the one thing artwork was brought in to avoid. The banner
    // spans the full width inside the frame, hence the two bevels.
    implicitWidth: banner.artNaturalWidth > 0
        ? banner.artNaturalWidth + theme.bevel * 2
        : 442
    // banner.implicitHeight, not theme.bannerHeight: the banner is two
    // different heights depending on whether it carries a brand panel, and
    // it is the thing that knows which.
    implicitHeight: banner.implicitHeight + contentArea.implicitHeight
        + buttonArea.height
    width: implicitWidth
    height: implicitHeight

    // Drop shadow: sits behind the face, offset via negative margins so it
    // reads as a soft frame shadow rather than a border.
    Rectangle {
        anchors.fill: face
        anchors.margins: -4
        color: theme.faceDark
        opacity: 0.25
        z: -1
    }

    Rectangle {
        id: face
        anchors.fill: parent
        color: theme.face
        // Square corners. The rounded frame belongs to Luna's title bars;
        // the logon dialog is drawn by GINA as a plain rectangular box, and
        // rounding it is a modern-UI reflex that reads wrong immediately.
        radius: 0
        border.width: 1
        border.color: theme.faceDark

        // Raised outer edge: a light inset border one pixel inside the true
        // frame, so the box reads as sitting above the backdrop rather than
        // being cut into it.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
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
                brand: root.bannerBrand
                copyright: root.bannerCopyright
                edition: root.bannerEdition
                wordmark: root.bannerWordmark
                wordmarkAccent: root.bannerWordmarkAccent
                vendor: root.bannerVendor
                image: root.bannerImage
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

                // The engraved groove XP rules across a dialog above its
                // button row. Two hairlines, not one: a dark pixel with a
                // light pixel beneath it. A single grey line in the same
                // place reads as a border rather than as a groove cut into
                // the face, which is the whole effect.
                Rectangle {
                    id: grooveTop
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: theme.grooveDark
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: grooveTop.bottom
                    height: 1
                    color: theme.grooveLight
                }

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
