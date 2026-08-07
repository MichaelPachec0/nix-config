import QtQuick

// title/subtitle are rendered here but not chosen here: LogonDialog.qml
// feeds this from Settings.config.branding.title/subtitle, a user-tier
// writable key, and SkinFatal.qml/ShutDownDialog.qml feed fixed literals.
// Without an explicit textFormat, Qt's AutoText detection would let a
// branding.title containing markup (including an <img src="file://...">)
// actually render as rich text on a pre-auth screen -- both Text elements
// below pin PlainText so that can never happen regardless of which caller
// is driving this file.
Item {
    id: root
    required property var theme
    property string title: ""
    property string subtitle: ""

    implicitWidth: 400
    implicitHeight: theme.bannerHeight
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: strip
        anchors.fill: parent
        gradient: theme.useGradients ? bannerGradient : null
        color: theme.useGradients ? "transparent" : theme.bannerTo

        Gradient {
            id: bannerGradient
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.bannerFrom }
            GradientStop { position: 1.0; color: theme.bannerTo }
        }

        // Flag mark: a plain rounded square, not a Marlett glyph -- Marlett
        // (verified against its cmap in XpComboBox.qml) has no logo/flag
        // character, only window-chrome and arrow marks, so this is drawn
        // as a themed shape rather than guessed at as a codepoint.
        Rectangle {
            id: flag
            width: theme.bannerHeight * 0.4
            height: theme.bannerHeight * 0.4
            radius: theme.radius
            anchors.left: parent.left
            anchors.leftMargin: theme.dialogPad
            anchors.verticalCenter: parent.verticalCenter
            color: theme.bannerText
            opacity: 0.85
        }

        Column {
            anchors.left: flag.right
            anchors.leftMargin: theme.rowSpacing
            anchors.right: parent.right
            anchors.rightMargin: theme.dialogPad
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.title
                textFormat: Text.PlainText
                color: theme.bannerText
                font.family: theme.uiBold
                font.bold: true
                font.pixelSize: theme.uiSize + 4
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.subtitle.length > 0
                text: root.subtitle
                textFormat: Text.PlainText
                color: theme.bannerSubtext
                font.family: theme.ui
                font.pixelSize: theme.uiSize - 1
                elide: Text.ElideRight
            }
        }
    }
}
