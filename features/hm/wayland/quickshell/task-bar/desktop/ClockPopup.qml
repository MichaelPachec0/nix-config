import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib/datemath.js" as DateMath

// Hover popup for the bar clock: Local / UTC / New York with live seconds, plus
// an ISO-week / day-of-year / Unix extras block. Mirrors the other bar popups
// (themed card, anchored under the clock, contentHovered + hide-timer). Time
// math is pure JS; the bar toggles `tick` every second and the bindings read it
// to re-evaluate. Read-only.
PopupWindow {
    id: pop
    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    property bool h12: false
    property bool tick: false // toggled every second by the bar; read to re-eval
    property bool contentHovered: cardHover.hovered

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    onImplicitWidthChanged: if (pop.visible) Qt.callLater(pop.reclamp)
    color: "transparent"
    visible: false
    grabFocus: false
    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function reclamp() {
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
    }
    function show() { if (!pop.visible) { pop.reclamp(); pop.visible = true; } }
    function hide() { pop.visible = false; }

    // --- pure time formatting (seconds-aware) ---
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function fmtHMS(h, m, s) {
        if (pop.h12) {
            var ap = h >= 12 ? "PM" : "AM";
            var hh = h % 12;
            if (hh === 0)
                hh = 12;
            return hh + ":" + pop.pad(m) + ":" + pop.pad(s) + " " + ap;
        }
        return pop.pad(h) + ":" + pop.pad(m) + ":" + pop.pad(s);
    }
    // US DST: 2nd Sun Mar (02:00 EST = 07:00 UTC) .. 1st Sun Nov (02:00 EDT =
    // 06:00 UTC). The two transitions fall on DIFFERENT UTC hours because the
    // clock is already on a different offset at each one -- approximating both at
    // 07:00 left the first Sunday of Nov an hour ahead until 07:00 UTC.
    function nycIsDst(d) {
        var y = d.getUTCFullYear();
        function nthSun(month, n, utcHour) {
            var first = new Date(Date.UTC(y, month, 1, 0, 0, 0));
            var firstSun = 1 + ((7 - first.getUTCDay()) % 7);
            return Date.UTC(y, month, firstSun + (n - 1) * 7, utcHour, 0, 0);
        }
        var t = d.getTime();
        return t >= nthSun(2, 2, 7) && t < nthSun(10, 1, 6);
    }
    function localStr(d) { return pop.fmtHMS(d.getHours(), d.getMinutes(), d.getSeconds()); }
    function utcStr(d) { return pop.fmtHMS(d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds()); }
    function nycStr(d) {
        var off = pop.nycIsDst(d) ? -4 : -5;
        var h = ((d.getUTCHours() + off) % 24 + 24) % 24;
        return pop.fmtHMS(h, d.getUTCMinutes(), d.getUTCSeconds());
    }
    function dayOfYear(d) {
        // UTC-anchored (matches datemath.isoWeek). The old local-time subtraction
        // was off by one across a DST boundary, where a 23h/25h day floors wrong.
        var start = Date.UTC(d.getUTCFullYear(), 0, 0);
        return Math.floor((d.getTime() - start) / 86400000);
    }

    Rectangle {
        id: card
        implicitWidth: col.implicitWidth + 24
        implicitHeight: col.implicitHeight + 20
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        HoverHandler { id: cardHover }

        ColumnLayout {
            id: col
            anchors { left: parent.left; top: parent.top; margins: 12 }
            spacing: 8

            // Zone rows: 2-col grid -- labels flush left, times right-aligned so
            // they line up in a column regardless of label/hour width.
            GridLayout {
                columns: 2
                columnSpacing: 18
                rowSpacing: 3

                Text {
                    text: "Local"
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textSecondary
                }
                Text {
                    text: { pop.tick; return pop.localStr(new Date()); }
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textPrimary
                }

                Text {
                    text: "UTC"
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textSecondary
                }
                Text {
                    text: { pop.tick; return pop.utcStr(new Date()); }
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textPrimary
                }

                Text {
                    text: "New York"
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textSecondary
                }
                Text {
                    text: { pop.tick; return pop.nycStr(new Date()); }
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textPrimary
                }
            }

            // divider
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: pop.theme.border
            }

            // Extras: ISO-8601 week + day-of-year, then live Unix seconds.
            Text {
                text: { pop.tick; return "ISO week " + DateMath.isoWeek(new Date()) + "     Day " + pop.dayOfYear(new Date()); }
                font.family: pop.theme.iconFont; font.pixelSize: 11
                color: pop.theme.textSecondary
            }
            Text {
                text: { pop.tick; return "Unix " + Math.floor(Date.now() / 1000); }
                font.family: pop.theme.iconFont; font.pixelSize: 11
                color: pop.theme.textSecondary
            }
        }
    }
}
