import QtQuick
// Quickshell's qmlscanner only resolves ONE bare same-directory type per
// document reliably (confirmed empirically: a second bare sibling
// reference in the same file intermittently reports "is not a type" even
// though the first one resolved fine, whichever type happened to be
// scanned first). An explicit `import "." as Kit` sidesteps it entirely,
// so every cross-file reference within widgets/ uses Kit.<Type> rather
// than relying on the implicit same-directory lookup.
import "." as Kit

// A modal message dialog: XpDialog's chrome plus a single OK button. Stays
// dumb by reusing XpDialog wholesale rather than duplicating its face/edge/
// shadow/banner drawing.
Item {
    id: root
    required property var theme
    property string text: ""
    signal accepted()

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: msgText
        text: root.text
        wrapMode: Text.WordWrap
        width: 300
        color: theme.infoText
        font.family: theme.ui
        font.pixelSize: theme.uiSize
    }

    Kit.XpDialog {
        id: dialog
        theme: root.theme
        contentItem: msgText
        buttons: [
            { text: "OK", isDefault: true, onClicked: function () { root.accepted(); } }
        ]
    }
}
