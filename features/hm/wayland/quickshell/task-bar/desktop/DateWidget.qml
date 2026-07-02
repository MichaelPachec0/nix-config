import QtQuick

// Bar date widget: the date string (click cycles its format) plus a hover
// calendar popup. Mirrors WeatherWidget's hover-persistence (widget hover OR
// popup content hover keeps it open, 250ms grace). Reads barWindow.tick so the
// string re-evaluates at midnight.
Item {
    id: root

    required property QtObject theme
    required property var barWindow
    required property var calState

    property int dateFmt: 0 // 0=Wed, Jul 1 2026  1=07-01-2026  2=2026-07-01

    implicitWidth: label.implicitWidth
    implicitHeight: 24

    function dateStr() {
        var d = new Date();
        if (root.dateFmt === 1)
            return Qt.formatDateTime(d, "MM-dd-yyyy");
        if (root.dateFmt === 2)
            return Qt.formatDateTime(d, "yyyy-MM-dd");
        return Qt.formatDateTime(d, "ddd, MMM d yyyy");
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: root.theme.textSecondary
        font.family: root.theme.textFont
        font.pixelSize: 13
        text: {
            root.barWindow.tick; // ride the clock tick (updates at midnight)
            return root.dateStr();
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dateFmt = (root.dateFmt + 1) % 3
        }
    }

    // Hover persistence: open while the cursor is over the widget OR the popup.
    readonly property bool over: mouse.containsMouse || popup.contentHovered
    onOverChanged: {
        if (root.over) {
            hideTimer.stop();
            popup.show();
        } else {
            hideTimer.restart();
        }
    }
    Timer {
        id: hideTimer
        interval: 250
        onTriggered: if (!root.over)
            popup.hide()
    }

    CalendarPopup {
        id: popup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        calState: root.calState
    }
}
