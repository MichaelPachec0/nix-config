import QtQuick
import QtQuick.Layouts
import "../lib" as Lib

// Tabs layout: compact metric strip at top, section tab bar, then full section detail.
// Tab index 0=CPU 1=Mem 2=GPU 3=Disk 4=Net 5=Proc 6=Temps 7=Power; aligns with the detail order.
ColumnLayout {
    id: root
    spacing: 6

    property QtObject theme
    property var stats
    property var gpu
    property var disk
    property var net
    property var sensors
    property var smu

    property int tab: 0

    // Clamp tab when a provider becomes unavailable
    Connections {
        target: root.gpu
        ignoreUnknownSignals: true
        function onAvailableChanged() { if (!root.gpu.available && root.tab === 2) root.tab = 0 }
    }
    Connections {
        target: root.disk
        ignoreUnknownSignals: true
        function onAvailableChanged() { if (!root.disk.available && root.tab === 3) root.tab = 0 }
    }
    Connections {
        target: root.net
        ignoreUnknownSignals: true
        function onAvailableChanged() { if (!root.net.available && root.tab === 4) root.tab = 0 }
    }
    Connections {
        target: root.sensors
        ignoreUnknownSignals: true
        function onAvailableChanged() { if (!root.sensors.available && !root.smu.available && root.tab === 6) root.tab = 0 }
    }
    Connections {
        target: root.smu
        ignoreUnknownSignals: true
        function onAvailableChanged() { if (!root.smu.available && root.tab === 7) root.tab = 0 }
    }

    // Compact metric strip
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: "CPU " + Math.round(root.stats.cpuPct) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
        }
        Lib.Sparkline {
            implicitWidth: 40; implicitHeight: 12
            values: root.stats.cpuHist; color: root.theme.accent
        }

        Text {
            text: "RAM " + Math.round(root.stats.ramPct) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
        }
        Lib.Sparkline {
            implicitWidth: 40; implicitHeight: 12
            values: root.stats.ramHist; color: root.theme.accent
        }

        Text {
            visible: root.gpu.available
            text: "GPU " + Math.round(root.gpu.util) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
        }
        Lib.Sparkline {
            visible: root.gpu.available
            implicitWidth: 40; implicitHeight: 12
            values: root.gpu.gpuHist; color: root.theme.accent
        }

        Item { Layout.fillWidth: true }
    }

    // Tab bar -- six fixed slots; GPU/Disk/Net hidden when provider unavailable
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Rectangle {
            implicitWidth: _t0.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 0 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t0; anchors.centerIn: parent; text: "CPU"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 0 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 0 }
        }
        Rectangle {
            implicitWidth: _t1.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 1 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t1; anchors.centerIn: parent; text: "Mem"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 1 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 1 }
        }
        Rectangle {
            visible: root.gpu.available
            implicitWidth: _t2.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 2 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t2; anchors.centerIn: parent; text: "GPU"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 2 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 2 }
        }
        Rectangle {
            visible: root.disk.available
            implicitWidth: _t3.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 3 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t3; anchors.centerIn: parent; text: "Disk"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 3 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 3 }
        }
        Rectangle {
            visible: root.net.available
            implicitWidth: _t4.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 4 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t4; anchors.centerIn: parent; text: "Net"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 4 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 4 }
        }
        Rectangle {
            implicitWidth: _t5.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 5 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t5; anchors.centerIn: parent; text: "Proc"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 5 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 5 }
        }
        Rectangle {
            visible: root.sensors.available || root.smu.available
            implicitWidth: _t6.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 6 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t6; anchors.centerIn: parent; text: "Temps"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 6 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 6 }
        }
        Rectangle {
            visible: root.smu.available
            implicitWidth: _t7.implicitWidth + 10; implicitHeight: 16; radius: 3
            color: root.tab === 7 ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : "transparent"
            Text { id: _t7; anchors.centerIn: parent; text: "Power"; font.family: root.theme.iconFont; font.pixelSize: 10; color: root.tab === 7 ? root.theme.accent : root.theme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.tab = 7 }
        }

        Item { Layout.fillWidth: true }
    }

    // Section detail: show ONLY the selected tab's section. A StackLayout here
    // fights each section's own `visible: provider.available` binding (which wins),
    // so every available section renders at once and overlaps. Gating each
    // section on `root.tab === N` and letting the ColumnLayout collapse the hidden
    // ones avoids that and sizes to the visible section.
    ColumnLayout {
        Layout.fillWidth: true

        SysCpuSection  { Layout.fillWidth: true; visible: root.tab === 0; theme: root.theme; stats: root.stats; smu: root.smu }
        SysMemSection  { Layout.fillWidth: true; visible: root.tab === 1; theme: root.theme; stats: root.stats }
        SysGpuSection  { Layout.fillWidth: true; visible: root.tab === 2 && root.gpu.available; theme: root.theme; gpu: root.gpu }
        SysDiskSection { Layout.fillWidth: true; visible: root.tab === 3 && root.disk.available; theme: root.theme; disk: root.disk }
        SysNetSection  { Layout.fillWidth: true; visible: root.tab === 4 && root.net.available; theme: root.theme; net: root.net }
        SysProcSection { Layout.fillWidth: true; visible: root.tab === 5; theme: root.theme; stats: root.stats }
        SysSensorSection { Layout.fillWidth: true; visible: root.tab === 6 && (root.sensors.available || root.smu.available); theme: root.theme; sensors: root.sensors; smu: root.smu }
        SysPowerSection  { Layout.fillWidth: true; visible: root.tab === 7 && root.smu.available; theme: root.theme; smu: root.smu }
    }
}
