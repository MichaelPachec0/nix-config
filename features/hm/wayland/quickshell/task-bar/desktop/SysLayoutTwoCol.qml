import QtQuick
import QtQuick.Layouts

// Two-column layout: CPU+Memory+GPU left, Sensors+Disk+Net right, Proc full-width below.
ColumnLayout {
    id: root
    spacing: 8

    property QtObject theme
    property var stats
    property var gpu
    property var disk
    property var net
    property var sensors

    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 8

            SysCpuSection { Layout.fillWidth: true; theme: root.theme; stats: root.stats }
            SysMemSection { Layout.fillWidth: true; theme: root.theme; stats: root.stats }
            SysGpuSection { Layout.fillWidth: true; theme: root.theme; gpu: root.gpu }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 8

            SysSensorSection { Layout.fillWidth: true; theme: root.theme; sensors: root.sensors }
            SysDiskSection   { Layout.fillWidth: true; theme: root.theme; disk: root.disk }
            SysNetSection    { Layout.fillWidth: true; theme: root.theme; net: root.net }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border }

    SysProcSection { Layout.fillWidth: true; theme: root.theme; stats: root.stats }
}
