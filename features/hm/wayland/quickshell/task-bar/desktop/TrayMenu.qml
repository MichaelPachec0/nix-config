import Quickshell
import QtQuick
import QtQuick.Layouts

// Gruvbox-themed DBus context menu for a system-tray item. (Quickshell's
// built-in SystemTrayItem.display() would draw a native Qt menu instead, which
// needs QApplication mode and ignores our theme.) One reused instance per dock.
//
// Submenus drill down in place via a "Back" row rather than flying out: a
// QsMenuEntry is itself a QsMenuHandle, so pushing one onto `stack` and
// rebinding the opener re-renders that submenu on the same focus-grabbed
// surface -- which avoids the nested-popup focus-grab problem. Flyout submenus
// are a later polish.
PopupWindow {
    id: root

    required property QtObject theme
    property var rootHandle: null

    // Submenu navigation stack; empty => showing rootHandle.
    property var stack: []
    readonly property var currentHandle: stack.length > 0 ? stack[stack.length - 1] : rootHandle

    // Rendered snapshot of the current menu's entries. We cache this rather than
    // binding the view straight to opener.children because live menus (e.g.
    // nm-applet re-emits its layout on every Wi-Fi scan) momentarily reset the
    // opener to zero children; rendering those transient empties would collapse
    // the popup. So we only adopt a NON-empty child list, and clear on navigation.
    property var view: []
    property bool opened: false

    onCurrentHandleChanged: root.view = []

    // grabFocus (or any hide) tears the menu down to a clean state. We keep
    // rootHandle so a same-item reopen can reseed from the still-bound opener.
    onVisibleChanged: if (!root.visible) {
        root.opened = false;
        root.stack = [];
        root.view = [];
    }

    // Reveal only once there's something to show. A genuinely empty menu (some
    // Electron apps expose an empty tray menu) thus never flashes a squished
    // box. `visible` is imperative so grabFocus can close it on an outside click.
    function reveal() {
        if (root.opened && root.view.length > 0)
            root.visible = true;
    }

    // Icon's right edge / drop point (dock coords). The menu grows leftward
    // from anchorRight so it stays on-screen under right-aligned tray icons.
    property real anchorRight: 0
    property real anchorTop: 0

    color: "transparent"
    grabFocus: true
    visible: false
    implicitWidth: surface.implicitWidth
    implicitHeight: surface.implicitHeight
    anchor.rect.x: Math.max(4, root.anchorRight - root.implicitWidth)
    anchor.rect.y: root.anchorTop

    QsMenuOpener {
        id: opener
        menu: root.currentHandle
        onChildrenChanged: {
            var v = opener.children.values;
            if (v.length > 0)
                root.view = v;
            root.reveal();
        }
    }

    function openAt(parentWin, rightX, topY, handle) {
        root.anchor.window = parentWin;
        root.anchorRight = rightX;
        root.anchorTop = topY;
        root.opened = true;
        // Reopening the SAME item: currentHandle won't change, so the opener
        // keeps its loaded children and won't re-emit childrenChanged -- reseed
        // the view from it directly. A different item changes currentHandle,
        // which reloads the opener; wait for childrenChanged then.
        if (handle === root.rootHandle && root.stack.length === 0) {
            root.view = opener.children.values;
        } else {
            root.stack = [];
            root.view = [];
            root.rootHandle = handle;
        }
        root.reveal();
    }
    function dismiss() {
        root.visible = false; // onVisibleChanged resets opened/stack/view
    }

    Rectangle {
        id: surface
        implicitWidth: Math.max(160, content.implicitWidth + 8)
        implicitHeight: content.implicitHeight + 8
        radius: 8
        color: root.theme.bgCard
        border.width: 1
        border.color: root.theme.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 4
            spacing: 1

            // "Back" row, only while inside a submenu.
            Rectangle {
                visible: root.stack.length > 0
                Layout.fillWidth: true
                implicitHeight: 26
                radius: 5
                color: backHover.hovered ? root.theme.bgItemHover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8
                    Text {
                        text: "<"
                        color: root.theme.textSecondary
                        font.pixelSize: 13
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Back"
                        color: root.theme.textSecondary
                        font.family: root.theme.textFont
                        font.pixelSize: 12
                    }
                }
                HoverHandler {
                    id: backHover
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stack = root.stack.slice(0, root.stack.length - 1)
                }
            }

            Repeater {
                model: root.view
                delegate: Item {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitWidth: rowLayout.implicitWidth + 16
                    implicitHeight: row.modelData.isSeparator ? 7 : 26

                    // Separator
                    Rectangle {
                        visible: row.modelData.isSeparator
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        height: 1
                        color: root.theme.border
                        opacity: 0.7
                    }

                    // Entry
                    Rectangle {
                        id: entryBg
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent
                        radius: 5
                        readonly property bool hot: rowHover.hovered && row.modelData.enabled
                        color: entryBg.hot ? root.theme.accent : "transparent"

                        RowLayout {
                            id: rowLayout
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            // Check / radio state (only for togglable entries):
                            // square for a checkbox, circle for a radio, filled
                            // when checked. Drawn (not a glyph) to stay themed.
                            Rectangle {
                                visible: row.modelData.buttonType !== 0
                                Layout.preferredWidth: 11
                                Layout.preferredHeight: 11
                                radius: row.modelData.buttonType === 2 ? 6 : 2
                                border.width: 1
                                border.color: entryBg.hot ? root.theme.textOnAccent : root.theme.textSecondary
                                color: row.modelData.checkState === 2 ? (entryBg.hot ? root.theme.textOnAccent : root.theme.accent) : "transparent"
                            }
                            Image {
                                visible: row.modelData.icon !== ""
                                source: row.modelData.icon
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.text
                                elide: Text.ElideRight
                                color: !row.modelData.enabled ? root.theme.border : (entryBg.hot ? root.theme.textOnAccent : root.theme.textPrimary)
                                font.family: root.theme.textFont
                                font.pixelSize: 12
                            }
                            // Submenu arrow
                            Text {
                                visible: row.modelData.hasChildren
                                text: ">"
                                color: entryBg.hot ? root.theme.textOnAccent : root.theme.textSecondary
                                font.pixelSize: 13
                            }
                        }

                        HoverHandler {
                            id: rowHover
                            enabled: row.modelData.enabled
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: row.modelData.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.modelData.hasChildren)
                                    root.stack = root.stack.concat([row.modelData]);
                                else {
                                    row.modelData.triggered();
                                    root.dismiss();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
