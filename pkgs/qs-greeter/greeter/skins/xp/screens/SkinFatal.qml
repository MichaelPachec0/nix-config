import QtQuick
import "../widgets" as Widgets

// Skinned recoverable-error screen: shown by Skin.qml when greetd is
// unavailable (session.backend.available is false) or the session list came
// back empty and settled that way (Sessions.ready with an empty list) --
// both are situations no amount of typing in the logon fields could ever
// recover from. Distinct from screens/CoreFatal.qml one level up: that one
// is core-owned, unskinned, and built from plain QtQuick types with no
// palette and no font beyond the default, so that whatever broke THIS skin
// (or any skin) cannot break it too. This screen is a healthy skin's own
// themed apology for having nothing usable to log into -- it is allowed to
// use the widget kit and the theme because the thing that is broken is the
// greeter's environment, not this file.
Item {
    id: root
    required property var theme
    required property string reason
    signal shutDownRequested()

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: msg
        text: root.reason
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        width: 300
        color: root.theme.infoText
        font.family: root.theme.ui
        font.pixelSize: root.theme.uiSize
    }

    Widgets.XpDialog {
        id: dialog
        theme: root.theme
        bannerTitle: "Log On to Windows"
        bannerSubtitle: ""
        contentItem: msg
        buttons: [
            { text: "Shut Down...", isDefault: true,
              onClicked: function () { root.shutDownRequested(); } }
        ]
    }
}
