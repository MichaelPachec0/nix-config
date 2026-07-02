import QtQuick
import QtQuick.Layouts
import Quickshell
import "../hub" as Hub

// Calendar popup shown on hover over the bar date widget. Read-only glance +
// navigation, so it is a non-grab popup anchored under the bar (mirrors
// WeatherPopup). Header row: prev/title/next + today-dot + [1][3][12] segmented
// layout picker. Body: the calendar for the current layout. Hover-only dismiss;
// contentHovered lets the cursor travel into the popup to click controls.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    required property var calState

    property date today: new Date()
    property date focusDate: new Date()
    property bool contentHovered: cardHover.hovered

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: false

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function show() {
        if (pop.visible)
            return;
        pop.today = new Date();
        pop.focusDate = new Date();
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }
    function hide() {
        pop.visible = false;
    }

    // Page by the visible span: 1 month (single), 3 months (three-up), 1 year.
    function step(dir) {
        var unit = pop.calState.layout === 2 ? 12 : (pop.calState.layout === 1 ? 3 : 1);
        var d = pop.focusDate;
        pop.focusDate = new Date(d.getFullYear(), d.getMonth() + dir * unit, 1);
    }
    function goToday() {
        pop.focusDate = new Date();
    }

    readonly property bool isCurrentPeriod: {
        var f = pop.focusDate, t = pop.today;
        if (pop.calState.layout === 2)
            return f.getFullYear() === t.getFullYear();
        var fi = f.getFullYear() * 12 + f.getMonth();
        var ti = t.getFullYear() * 12 + t.getMonth();
        if (pop.calState.layout === 1)
            return Math.abs(fi - ti) <= 1; // today anywhere in the visible trio
        return fi === ti; // single month
    }
    readonly property string title: {
        if (pop.calState.layout === 2)
            return Qt.formatDate(pop.focusDate, "yyyy");
        if (pop.calState.layout === 1) {
            var a = new Date(pop.focusDate.getFullYear(), pop.focusDate.getMonth() - 1, 1);
            var b = new Date(pop.focusDate.getFullYear(), pop.focusDate.getMonth() + 1, 1);
            if (a.getFullYear() === b.getFullYear())
                return Qt.formatDate(a, "MMM") + " - " + Qt.formatDate(b, "MMM yyyy");
            return Qt.formatDate(a, "MMM yyyy") + " - " + Qt.formatDate(b, "MMM yyyy");
        }
        return Qt.formatDate(pop.focusDate, "MMMM yyyy");
    }

    // Segments: `on` gates whether a layout is selectable yet (Tasks 4-5 flip
    // three/year to true as their views land).
    readonly property var segments: [
        { label: "1", val: 0, on: true },
        { label: "3", val: 1, on: true },
        { label: "12", val: 2, on: false }
    ]

    Rectangle {
        id: card
        implicitWidth: col.implicitWidth + 24
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        HoverHandler {
            id: cardHover
        }

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                top: parent.top
                margins: 12
            }
            spacing: 8

            // Header controls.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: String.fromCharCode(0xF053) // fa chevron-left
                    font.family: pop.theme.faFont
                    font.pixelSize: 12
                    color: prevMouse.containsMouse ? pop.theme.textPrimary : pop.theme.textSecondary
                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.step(-1)
                    }
                }
                Text {
                    Layout.preferredWidth: 150
                    horizontalAlignment: Text.AlignHCenter
                    text: pop.title
                    font.family: pop.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: pop.theme.textPrimary
                }
                Text {
                    text: String.fromCharCode(0xF054) // fa chevron-right
                    font.family: pop.theme.faFont
                    font.pixelSize: 12
                    color: nextMouse.containsMouse ? pop.theme.textPrimary : pop.theme.textSecondary
                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.step(1)
                    }
                }
                Text {
                    text: String.fromCharCode(0xF111) // fa circle (today dot)
                    font.family: pop.theme.faFont
                    font.pixelSize: 9
                    visible: !pop.isCurrentPeriod
                    color: todayMouse.containsMouse ? pop.theme.accent : pop.theme.textSecondary
                    MouseArea {
                        id: todayMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.goToday()
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Segmented [1][3][12].
                Row {
                    spacing: 2
                    Repeater {
                        model: pop.segments
                        delegate: Rectangle {
                            id: seg
                            required property var modelData
                            width: 26
                            height: 18
                            radius: 4
                            color: pop.calState.layout === seg.modelData.val ? pop.theme.accent : pop.theme.bgItem
                            opacity: seg.modelData.on ? 1.0 : 0.4
                            Text {
                                anchors.centerIn: parent
                                text: seg.modelData.label
                                font.family: pop.theme.textFont
                                font.pixelSize: 11
                                color: pop.calState.layout === seg.modelData.val ? pop.theme.textOnAccent : pop.theme.textSecondary
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: seg.modelData.on
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.calState.layout = seg.modelData.val
                            }
                        }
                    }
                }
            }

            // Body: the layout selected by calState.layout.
            Loader {
                id: body
                sourceComponent: pop.calState.layout === 1 ? threeView : singleView
            }
        }

        Component {
            id: singleView
            Hub.CalendarGrid {
                theme: pop.theme
                when: pop.focusDate
                today: pop.today
                showWeeks: true
            }
        }

        Component {
            id: threeView
            RowLayout {
                spacing: 12
                Repeater {
                    model: [-1, 0, 1]
                    delegate: Hub.CalendarGrid {
                        id: g3
                        required property int modelData
                        theme: pop.theme
                        when: new Date(pop.focusDate.getFullYear(), pop.focusDate.getMonth() + g3.modelData, 1)
                        today: pop.today
                        showWeeks: true
                    }
                }
            }
        }
    }
}
