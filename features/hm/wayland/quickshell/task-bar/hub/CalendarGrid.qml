import QtQuick
import QtQuick.Layouts
import "../lib/datemath.js" as DateMath

// Month calendar grid. A row of weekday headers (S M T W T F S) followed by day
// cells for `when`'s month, today drawn as an accent pill. With showWeeks it
// prepends an ISO week-number column (corner cell + one week label per row,
// labelled by the row's Thursday). `today` is separate from `when` so the grid
// highlights today ONLY in the month that contains it (needed when several
// months render at once). Sizes itself to content via grid.implicit*.
Item {
    id: root

    required property QtObject theme
    property date when: new Date()
    property date today: root.when
    property bool showWeeks: false
    property int cellWidth: 28
    property int cellHeight: 16
    property int fontSize: 10
    property var cells: []

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    // Per-weekday tint: a soft rainbow across the columns, with both S columns
    // (Sun + Sat) sharing red so weekends read as a pair. Applied to the header
    // letters and the day numbers when colorizeDays is true.
    property bool colorizeDays: true
    readonly property var dayColors: [
        root.theme.accentRed,     // Sun
        root.theme.accentOrange,  // Mon
        root.theme.accentYellow,  // Tue
        root.theme.accentGreen,   // Wed
        root.theme.accentSlider,  // Thu (aqua)
        root.theme.accentBlue,    // Fri
        root.theme.accentRed      // Sat
    ]
    // Desaturate toward the neutral text colour so the tint stays subtle on the
    // dark card (headers a touch more muted than the day numbers).
    function dayHue(col, isHead) {
        var c = root.dayColors[col];
        var n = root.theme.textSecondary;
        var a = isHead ? 0.82 : 0.96;
        return Qt.rgba(c.r * a + n.r * (1 - a), c.g * a + n.g * (1 - a), c.b * a + n.b * (1 - a), 1);
    }

    function rebuild() {
        var d = root.when;
        var y = d.getFullYear();
        var m = d.getMonth();
        var t = root.today;
        var isCurMonth = (t.getFullYear() === y && t.getMonth() === m);
        var curDay = t.getDate();
        var firstDay = new Date(y, m, 1).getDay();       // 0=Sun
        var daysInMonth = new Date(y, m + 1, 0).getDate();
        var heads = ["S", "M", "T", "W", "T", "F", "S"];
        var out = [];
        if (root.showWeeks)
            out.push({ kind: "corner", t: "", today: false });
        for (var i = 0; i < 7; i++)
            out.push({ kind: "head", t: heads[i], today: false, col: i });
        // Linear day sequence: leading blanks, days, trailing blanks to fill the
        // final week (so each row -- and its week label -- is complete).
        var seq = [];
        for (i = 0; i < firstDay; i++)
            seq.push(0);
        for (i = 1; i <= daysInMonth; i++)
            seq.push(i);
        while (seq.length % 7 !== 0)
            seq.push(0);
        for (var r = 0; r < seq.length; r += 7) {
            if (root.showWeeks) {
                var thu = new Date(y, m, 1 - firstDay + r + 4); // Thursday of this row
                out.push({ kind: "week", t: String(DateMath.isoWeek(thu)), today: false });
            }
            for (var c = 0; c < 7; c++) {
                var day = seq[r + c];
                if (day === 0)
                    out.push({ kind: "blank", t: "", today: false });
                else
                    out.push({ kind: "day", t: String(day), today: isCurMonth && day === curDay, col: c });
            }
        }
        root.cells = out;
    }

    Component.onCompleted: rebuild()
    onWhenChanged: rebuild()
    onTodayChanged: rebuild()
    onShowWeeksChanged: rebuild()

    GridLayout {
        id: grid
        columns: root.showWeeks ? 8 : 7
        rowSpacing: 3
        columnSpacing: 3

        Repeater {
            model: root.cells.length
            delegate: Item {
                id: cellItem
                required property int index
                readonly property var cell: root.cells[cellItem.index]
                readonly property bool isWeek: cellItem.cell.kind === "week"
                readonly property bool isCorner: cellItem.cell.kind === "corner"
                readonly property bool isHead: cellItem.cell.kind === "head"
                readonly property bool isDay: cellItem.cell.kind === "day"
                readonly property bool isMuted: cellItem.isHead || cellItem.isWeek || cellItem.isCorner
                readonly property bool tinted: root.colorizeDays && (cellItem.isHead || cellItem.isDay)
                Layout.preferredWidth: (cellItem.isWeek || cellItem.isCorner) ? Math.round(root.cellWidth * 0.8) : root.cellWidth
                Layout.preferredHeight: root.cellHeight

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
                    font.pixelSize: cellItem.isWeek ? Math.max(8, root.fontSize - 1) : root.fontSize
                    font.weight: cellItem.isMuted ? Font.Light : (cellItem.cell.today ? Font.ExtraBold : Font.Normal)
                    color: cellItem.cell.today ? root.theme.textOnAccent : (cellItem.tinted ? root.dayHue(cellItem.cell.col, cellItem.isHead) : Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g, root.theme.textSecondary.b, cellItem.isWeek ? 0.6 : (cellItem.isMuted ? 0.8 : 0.92)))
                }
            }
        }
    }
}
