import QtQuick

Item {
    id: root
    required property var theme
    property string text: ""
    property bool isDefault: false
    property bool enabled: true
    signal clicked()

    // Exposed for headless testing only (there is no other way to observe
    // whether the anonymous pulse animation below is actually running from
    // outside this file); it is not part of the widget's own behavior.
    readonly property bool pulseRunning: pulseAnim.running

    implicitWidth: Math.max(80, label.implicitWidth + 24)
    implicitHeight: theme.controlHeight + 2
    // Self-sizing default so this widget renders correctly the moment it is
    // dropped somewhere without a Layout around it (a plain Item never picks
    // up its implicit size on its own); an explicit width/height assignment
    // by a caller still wins over this binding, same as any QtQuick control.
    width: implicitWidth
    height: implicitHeight
    // Dims the whole button -- frame and label together -- rather than just
    // the frame, and is externally observable on the widget itself (a
    // caller, or a test, checking `enabled ? disabled` state only has to
    // look at this one property).
    opacity: root.enabled ? 1.0 : 0.55

    Rectangle {
        id: body
        anchors.fill: parent
        radius: theme.useRoundedButtons ? theme.radius : 0
        border.width: 1
        border.color: root.isDefault ? theme.defaultGlowFrom : theme.buttonBorder
        gradient: theme.useGradients ? buttonGradient : null
        color: theme.useGradients ? "transparent" : theme.buttonTo

        Gradient {
            id: buttonGradient
            GradientStop { position: 0.0; color: ma.pressed ? theme.buttonTo : theme.buttonFrom }
            GradientStop { position: 1.0; color: ma.pressed ? theme.buttonFrom : theme.buttonTo }
        }

        // XP's default button pulses its glow. Behind a theme switch, and
        // at a theme-driven speed, so a palette can opt out or retime it
        // without touching widget code.
        SequentialAnimation on border.color {
            id: pulseAnim
            running: root.isDefault && theme.pulseDefaultButton && root.enabled
            loops: Animation.Infinite
            ColorAnimation { to: theme.defaultGlowTo; duration: theme.pulseDuration }
            ColorAnimation { to: theme.defaultGlowFrom; duration: theme.pulseDuration }
        }

        // theme.focusRing made visible: declared in Theme.qml and read by
        // nothing until this fix. A separate overlay Rectangle rather than
        // driving `body.border.color` itself, so it never fights the
        // pulse-glow `SequentialAnimation on border.color` immediately
        // above -- that animation is a property value source that owns
        // border.color outright whenever it is running, and layering a
        // second driver onto the same property is exactly the kind of
        // interaction this avoids by construction rather than by ordering.
        // Currently reachable only if a future caller Tab-focuses a button
        // (nothing in this codebase does yet -- OK/Cancel are today only
        // ever reached by mouse or by the dialog root's own Keys.
        // onReturnPressed calling _ok() directly), wired now so the ring
        // exists the moment that changes.
        Rectangle {
            id: focusRing
            visible: root.activeFocus
            anchors.fill: parent
            anchors.margins: -2
            radius: body.radius
            color: "transparent"
            border.width: 2
            border.color: theme.focusRing
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        textFormat: Text.PlainText
        color: theme.buttonText
        font.family: theme.ui
        font.pixelSize: theme.uiSize
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
    }

    Keys.onReturnPressed: if (root.enabled) root.clicked()
    Keys.onSpacePressed: if (root.enabled) root.clicked()
}
