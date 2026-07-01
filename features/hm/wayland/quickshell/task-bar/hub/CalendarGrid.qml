import QtQuick
import QtQuick.Layouts

// Month calendar grid for the hub Calendar/Weather card. Pure date math: a row
// of weekday headers (S M T W T F S) followed by day cells for `when`'s month,
// with today drawn as an accent pill. Adapted from surface-dots (Gruvbox theme
// tokens, dark-only). Sizes itself to its content via grid.implicit*.
Item {
    id: root

    required property QtObject theme
    property date when: new Date()
    property var cells: []

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    function rebuild() {
        var d = root.when;
        var y = d.getFullYear();
        var m = d.getMonth();
        var today = d.getDate();
        var firstDay = new Date(y, m, 1).getDay();
        var daysInMonth = new Date(y, m + 1, 0).getDate();
        var out = [];
        var heads = ["S", "M", "T", "W", "T", "F", "S"];
        for (var i = 0; i < 7; i++)
            out.push({
                kind: "head",
                t: heads[i],
                today: false
            });
        for (i = 0; i < firstDay; i++)
            out.push({
                kind: "blank",
                t: "",
                today: false
            });
        for (i = 1; i <= daysInMonth; i++)
            out.push({
                kind: "day",
                t: String(i),
                today: (i === today)
            });
        root.cells = out;
    }

    Component.onCompleted: rebuild()
    onWhenChanged: rebuild()

    GridLayout {
        id: grid
        columns: 7
        rowSpacing: 3
        columnSpacing: 3

        Repeater {
            model: root.cells.length
            delegate: Item {
                id: cellItem
                required property int index
                readonly property var cell: root.cells[cellItem.index]
                Layout.preferredWidth: 28
                Layout.preferredHeight: 16

                // Today pill behind the number.
                Rectangle {
                    anchors.centerIn: parent
                    width: cellItem.height + 4
                    height: cellItem.height
                    radius: 5
                    visible: cellItem.cell.today === true
                    color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.75)
                }

                Text {
                    anchors.centerIn: parent
                    text: cellItem.cell.t
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                    font.weight: cellItem.cell.kind === "head" ? Font.Light : (cellItem.cell.today ? Font.ExtraBold : Font.Normal)
                    color: cellItem.cell.kind === "head" ? Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g, root.theme.textSecondary.b, 0.8) : (cellItem.cell.today ? root.theme.textOnAccent : Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g, root.theme.textSecondary.b, 0.92))
                }
            }
        }
    }
}
