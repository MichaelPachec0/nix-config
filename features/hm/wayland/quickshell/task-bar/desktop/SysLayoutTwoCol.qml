import QtQuick
import QtQuick.Layouts

// Two-column layout: CPU+Memory+GPU+Disk left, Sensors+Power+Net right, Proc full-width below.
ColumnLayout {
    id: root
    spacing: 8

    property QtObject theme
    property var stats
    property var gpu
    property var disk
    property var net
    property var sensors
    property var smu

    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 8
            // Hard stop: even if a row ever exceeds its half, clip keeps it from
            // painting over the right column (the sections reserve widths so this
            // should never actually trigger -- it is belt-and-suspenders).
            clip: true

            SysCpuSection  { Layout.fillWidth: true; theme: root.theme; stats: root.stats; smu: root.smu }
            SysMemSection  { Layout.fillWidth: true; theme: root.theme; stats: root.stats }
            SysGpuSection  { Layout.fillWidth: true; theme: root.theme; gpu: root.gpu }
            SysDiskSection { Layout.fillWidth: true; theme: root.theme; disk: root.disk }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 8
            clip: true

            SysSensorSection { Layout.fillWidth: true; theme: root.theme; sensors: root.sensors; smu: root.smu }
            SysPowerSection  { Layout.fillWidth: true; theme: root.theme; smu: root.smu }
            SysNetSection    { Layout.fillWidth: true; theme: root.theme; net: root.net }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border }

    SysProcSection { Layout.fillWidth: true; theme: root.theme; stats: root.stats }
}
