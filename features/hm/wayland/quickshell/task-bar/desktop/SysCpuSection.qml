import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/sysfmt.js" as SysFmt

// CPU section: header row (util, load, temp), per-core mini bars, history sparkline.
// Consumed by the SysPopup composition layer. No visible gate (CPU always present).
ColumnLayout {
    id: root
    spacing: 6

    required property QtObject theme
    required property var stats
    property var smu: null

    // A core counts as asleep when its SMU C6 (deep-sleep) residency is >= 90%.
    // Needs the SMU snapshot; on cpufreq fallback (no C-state data) never idle.
    function coreIdle(core) {
        return !!(root.smu && root.smu.available && root.smu.perCoreC6
            && typeof root.smu.perCoreC6[core.coreId] === "number"
            && root.smu.perCoreC6[core.coreId] >= 90);
    }
    // A CCX is asleep when every one of its cores is idle.
    function ccxIdle(ccx) {
        for (var i = 0; i < ccx.cores.length; i++)
            if (!root.coreIdle(ccx.cores[i]))
                return false;
        return true;
    }

    // Effective clock (GHz string) for a core: "Zzz" when asleep, else the SMU
    // per-core freq when available, else the max cpufreq of the core's threads,
    // else "--".
    function coreClockLabel(core) {
        if (root.coreIdle(core))
            return "Zzz";
        var mhz = 0;
        if (root.smu && root.smu.available && root.smu.perCoreFreq
            && typeof root.smu.perCoreFreq[core.coreId] === "number"
            && root.smu.perCoreFreq[core.coreId] > 0) {
            mhz = root.smu.perCoreFreq[core.coreId];
        } else {
            var f = root.stats.perThreadFreq || [];
            for (var i = 0; i < core.threads.length; i++) {
                var v = f[core.threads[i]] || 0;
                if (v > mhz) mhz = v;
            }
        }
        if (mhz <= 0) return "--";
        return (mhz / 1000).toFixed(2) + " GHz";
    }

    // Reserved widths: size the numeric fields to their widest string so a value
    // growing a digit never reflows the row. Measured (not hard-coded px) so a
    // font/DPI change stays correct even though JetBrainsMono is monospace.
    readonly property real _wPct: _mPct.advanceWidth
    readonly property real _wTemp: _mTemp.advanceWidth
    TextMetrics { id: _mPct;  font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold; text: "CPU 100%" }
    TextMetrics { id: _mTemp; font.family: root.theme.iconFont; font.pixelSize: 11; text: "zen 100 C" }
    readonly property real _wCcx: _mCcx.advanceWidth
    TextMetrics { id: _mCcx; font.family: root.theme.iconFont; font.pixelSize: 10; font.weight: Font.DemiBold; text: "CCX0" }
    // Per-core clock cell reserves the widest "x.xx GHz" so each core gets
    // comfortable, uniform room and the two CCX rows' columns line up.
    readonly property real _wClock: _mClock.advanceWidth
    TextMetrics { id: _mClock; font.family: root.theme.iconFont; font.pixelSize: 9; text: "9.99 GHz" }

    // Header: CPU%, load averages, temperature.
    // The load field is the flexible absorber (elides under pressure); CPU% and
    // the temperature reserve their max width so a growing digit can never push
    // the right-aligned temperature past the column edge into the next column.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: "CPU " + Math.round(root.stats.cpuPct) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", root.stats.cpuPct))
            Layout.minimumWidth: root._wPct
        }
        Text {
            text: "load " + (root.stats.load[0] || 0).toFixed(2) + " "
                + (root.stats.load[1] || 0).toFixed(2) + " " + (root.stats.load[2] || 0).toFixed(2)
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: "zen " + Math.round(root.stats.cpuTemp) + " C"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: SysFmt.sevColor(root.theme,SysFmt.severity("temp", root.stats.cpuTemp))
            horizontalAlignment: Text.AlignRight
            Layout.minimumWidth: root._wTemp
            Layout.preferredWidth: root._wTemp
        }
    }

    // Per-thread bars grouped by CCX -> core. Each core: its thread bars, a core
    // id, and the core's effective clock beneath. Explicit ids avoid modelData
    // shadowing across the nested repeaters.
    Column {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.stats.cpuTopology
            delegate: RowLayout {
                id: ccxRow
                required property var modelData
                readonly property var ccx: modelData
                width: parent.width
                spacing: 8
                Text {
                    text: "CCX" + ccxRow.ccx.ccx
                    font.family: root.theme.iconFont; font.pixelSize: 10; font.weight: Font.DemiBold
                    color: root.theme.textSecondary
                    // Whole-row dim when every core in the CCX is asleep.
                    opacity: root.ccxIdle(ccxRow.ccx) ? 0.4 : 1.0
                    Layout.minimumWidth: root._wCcx
                    Layout.alignment: Qt.AlignVCenter
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: ccxRow.ccx.cores
                        delegate: Column {
                            id: coreCell
                            required property var modelData
                            readonly property var core: modelData
                            // Dim the whole core cell (bars + id + clock) when asleep.
                            opacity: root.coreIdle(coreCell.core) ? 0.4 : 1.0
                            Layout.fillWidth: true
                            Layout.minimumWidth: root._wClock
                            spacing: 2
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 2
                                Repeater {
                                    model: coreCell.core.threads
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property int logical: modelData
                                        readonly property real util: (root.stats.perCore && root.stats.perCore[logical] !== undefined)
                                            ? root.stats.perCore[logical] : 0
                                        width: 6
                                        height: 16
                                        radius: 1
                                        color: Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g,
                                                       root.theme.textSecondary.b, 0.2)
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.max(1, parent.height * parent.util / 100)
                                            radius: 1
                                            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", parent.util))
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "c" + coreCell.core.coreId
                                font.family: root.theme.iconFont; font.pixelSize: 9
                                color: root.theme.textSecondary
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.coreClockLabel(coreCell.core)
                                font.family: root.theme.iconFont; font.pixelSize: 9
                                color: root.theme.textSecondary
                            }
                        }
                    }
                }
            }
        }
    }

    // History sparkline
    Lib.Sparkline {
        Layout.fillWidth: true
        implicitHeight: 22
        values: root.stats.cpuHist
        color: root.theme.accent
    }
}
