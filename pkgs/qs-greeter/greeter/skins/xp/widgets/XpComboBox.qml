import QtQuick

Item {
    id: root
    required property var theme
    property var model: []
    property int currentIndex: -1
    property bool enabled: true
    readonly property string currentName:
        (root.currentIndex >= 0 && root.currentIndex < root.model.length)
            ? String(root.model[root.currentIndex]) : ""
    readonly property bool popupOpen: popup.visible
    // Exposed for headless testing only: lets a caller confirm keyboard
    // navigation actually moves the popup's highlighted row without
    // reaching into the internal ListView by id.
    readonly property int highlightIndex: list.currentIndex
    signal activated(int index)

    implicitWidth: 180
    implicitHeight: theme.controlHeight + 2
    width: implicitWidth
    height: implicitHeight
    // Externally observable, same reasoning as XpButton/XpTextField.
    opacity: root.enabled ? 1.0 : 0.6

    activeFocusOnTab: true
    focus: true

    function openPopup() { if (root.enabled) popup.visible = true; }
    function closePopup() { popup.visible = false; }
    function togglePopup() { if (popup.visible) root.closePopup(); else root.openPopup(); }

    // Moves the popup's highlighted row by `delta` (+1/-1) and, once a
    // selection is confirmed, updates currentIndex. Keys.onUp/DownPressed
    // below call this directly, and so does the headless test harness --
    // there is no synthetic-keyboard path under the offscreen QPA platform,
    // so the harness exercises this function rather than real key delivery.
    function moveHighlight(delta) {
        if (!popup.visible) { root.openPopup(); return; }
        var n = root.model.length;
        if (n === 0) return;
        var i = list.currentIndex;
        i = (i < 0) ? 0 : ((i + delta % n) + n) % n;
        list.currentIndex = i;
    }

    function confirmHighlight() {
        if (!popup.visible) { root.togglePopup(); return; }
        if (list.currentIndex >= 0) {
            root.currentIndex = list.currentIndex;
            root.activated(root.currentIndex);
        }
        root.closePopup();
    }

    Rectangle {
        id: box
        anchors.fill: parent
        color: root.enabled ? theme.fieldBg : theme.fieldDisabled
        border.width: 1
        border.color: theme.fieldBorder

        Text {
            id: currentText
            anchors.left: parent.left
            anchors.right: arrowButton.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            elide: Text.ElideRight
            text: root.currentName
            color: theme.fieldText
            font.family: theme.ui
            font.pixelSize: theme.uiSize
        }

        Rectangle {
            id: arrowButton
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: theme.controlHeight
            border.width: 1
            border.color: theme.buttonBorder
            gradient: theme.useGradients ? arrowGradient : null
            color: theme.useGradients ? "transparent" : theme.buttonTo

            Gradient {
                id: arrowGradient
                GradientStop { position: 0.0; color: arrowArea.pressed ? theme.buttonTo : theme.buttonFrom }
                GradientStop { position: 1.0; color: arrowArea.pressed ? theme.buttonFrom : theme.buttonTo }
            }

            // Marlett glyph mapping verified against the shipped font, not
            // memory: `ttx -t cmap marlett.ttf` maps codepoint 0x36 ('6') to
            // glyph "six", and that glyph's own outline (glyf table) is a
            // 3-point contour -- two corners at the top edge, one apex at
            // the bottom -- i.e. a solid downward-pointing triangle. Also
            // rasterized and visually confirmed (not just read from the
            // outline coordinates) before picking it: it renders as a clean
            // filled down-arrow with no baseline/underline, matching the
            // combo box's own drop-down arrow in classic Windows chrome.
            Text {
                anchors.centerIn: parent
                text: "6"
                font.family: theme.glyph
                font.pixelSize: theme.uiSize
                color: theme.buttonText
            }

            MouseArea {
                id: arrowArea
                anchors.fill: parent
                enabled: root.enabled
                onClicked: root.togglePopup()
            }
        }

        MouseArea {
            anchors.left: parent.left
            anchors.right: arrowButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            enabled: root.enabled
            onClicked: root.togglePopup()
        }
    }

    Rectangle {
        id: popup
        visible: false
        x: 0
        y: box.height
        z: 1000
        width: root.width
        height: Math.min(list.contentHeight, theme.controlHeight * theme.comboVisibleRows)
        color: theme.fieldBg
        border.width: 1
        border.color: theme.fieldBorder

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            model: root.model
            currentIndex: root.currentIndex
            delegate: Rectangle {
                width: list.width
                height: theme.controlHeight
                color: ListView.isCurrentItem ? theme.bannerFrom : theme.fieldBg
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    verticalAlignment: Text.AlignVCenter
                    text: String(modelData)
                    color: ListView.isCurrentItem ? theme.bannerText : theme.fieldText
                    font.family: theme.ui
                    font.pixelSize: theme.uiSize
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        list.currentIndex = index;
                        root.confirmHighlight();
                    }
                }
            }
        }
    }

    Keys.onDownPressed: root.moveHighlight(1)
    Keys.onUpPressed: root.moveHighlight(-1)
    Keys.onReturnPressed: root.confirmHighlight()
    Keys.onEscapePressed: root.closePopup()
}
