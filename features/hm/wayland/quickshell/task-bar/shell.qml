import Quickshell
import QtQuick
import Qt5Compat.GraphicalEffects

ShellRoot {
    PanelWindow {
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 44
        color: "#cc1d2021"

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: 200
            height: 26
            radius: 13
            color: "#87b158"
            Text {
                anchors.centerIn: parent
                text: "quickshell alive"
                color: "#1d2021"
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
