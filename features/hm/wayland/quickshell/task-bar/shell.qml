import Quickshell
import QtQuick
import Qt5Compat.GraphicalEffects
import "lib" as Lib

ShellRoot {
    Lib.ThemeEngine {
        id: theme
    }

    PanelWindow {
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 44
        color: theme.bgMain

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: 240
            height: 26
            radius: 13
            color: theme.accent
            Text {
                anchors.centerIn: parent
                text: "seam: " + theme.accent + " / " + theme.textFont
                color: theme.textOnAccent
                font.family: theme.textFont
            }
        }

        DropShadow {
            anchors.fill: pill
            source: pill
            horizontalOffset: 0
            verticalOffset: 2
            radius: 10
            samples: 21
            color: "#80000000"
        }
    }
}
