import QtQuick

// A Luna push button, built from XP.css's themes/XP/_buttons.scss rather
// than from an impression of one. Three details do all the work, and all
// three are things a from-memory recreation gets wrong:
//
//   1. The resting face is white at the top, holds almost all the way down,
//      then drops hard in the last 14% -- the stop sits at 86%, not near
//      the middle. A gradient that breaks near the middle looks lit from
//      the side rather than from above. See theme.btnFaceTop/Mid/Bottom.
//   2. Pressed is NOT that ramp reversed. It is its own curve: a dark cap
//      at the very top, an immediate step lighter at 8%, flat through the
//      body, and a lift at the last pixel.
//   3. Hover and focus are rings INSIDE the border, not halos outside it --
//      amber warming downward for hover (theme.hoverGlowOuter through
//      hoverGlowBottom), blue for focus. The default button wears the focus
//      ring; XP has no pulsing glow.
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
    // Same convention: lets a gallery/unit test assert that hover actually
    // reaches the ring, which is not otherwise visible from outside.
    readonly property bool testHovered: ma.containsMouse
    // Which inset ring is showing, if any: "" | "hover" | "focus". One
    // string rather than two booleans, because the two are mutually
    // exclusive by construction below and a test asserting that should not
    // be able to express "both".
    readonly property string testRing: ma.containsMouse
        ? "hover"
        : ((root.isDefault || root.activeFocus) ? "focus" : "")

    implicitWidth: Math.max(75, label.implicitWidth + 22)
    implicitHeight: theme.controlHeight
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
        border.color: theme.buttonBorder
        gradient: theme.useGradients ? (ma.pressed ? pressedFace : restingFace) : null
        color: theme.useGradients ? "transparent" : theme.btnFaceMid

        Gradient {
            id: restingFace
            GradientStop { position: 0.0; color: theme.btnFaceTop }
            GradientStop { position: 0.86; color: theme.btnFaceMid }
            GradientStop { position: 1.0; color: theme.btnFaceBottom }
        }

        Gradient {
            id: pressedFace
            GradientStop { position: 0.0; color: theme.btnPressTop }
            GradientStop { position: 0.08; color: theme.btnPressUpper }
            GradientStop { position: 0.94; color: theme.btnPressLower }
            GradientStop { position: 1.0; color: theme.btnPressBottom }
        }

        // The inset ring. XP.css draws it as four overlapping box-shadows
        // whose offsets make the color warm (hover) or cool (focus) toward
        // the bottom of the button; two concentric 1px rectangles with the
        // upper and lower tones reproduce that at this size, where the
        // outermost of the four tones is a single pixel that never reads as
        // its own band.
        //
        // Hover beats focus deliberately: an XP default button you are
        // pointing at glows amber like any other button, it does not stay
        // blue underneath the cursor.
        Item {
            id: ring
            anchors.fill: parent
            visible: root.enabled && (ma.containsMouse || root.isDefault || root.activeFocus)
            readonly property bool warm: ma.containsMouse

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, body.radius - 1)
                color: "transparent"
                border.width: 1
                border.color: ring.warm ? theme.hoverGlowUpper : theme.focusGlowUpper
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(0, body.radius - 2)
                color: "transparent"
                border.width: 1
                border.color: ring.warm ? theme.hoverGlowLower : theme.focusGlowLower
            }

            // Off by default (theme.pulseDefaultButton) -- XP's default
            // button wears this ring statically. Left wired because it was
            // this skin's previous behavior and is one property away.
            SequentialAnimation on opacity {
                id: pulseAnim
                running: root.isDefault && !ma.containsMouse
                    && theme.pulseDefaultButton && root.enabled
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: theme.pulseDuration; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: theme.pulseDuration; easing.type: Easing.InOutSine }
            }
        }

        // The keyboard focus indicator proper: Windows draws a dotted
        // rectangle just inside the face, distinct from the colored ring
        // above (which a default button shows whether or not it has focus).
        Rectangle {
            visible: root.activeFocus
            anchors.fill: parent
            anchors.margins: 3
            color: "transparent"
            border.width: 1
            border.color: theme.focusRing
            opacity: 0.55
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        // Pressed nudges the label down-right by a pixel, the way every
        // Windows push button has since 3.1.
        anchors.horizontalCenterOffset: ma.pressed ? 1 : 0
        anchors.verticalCenterOffset: ma.pressed ? 1 : 0
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
        hoverEnabled: true
        onClicked: root.clicked()
    }

    Keys.onReturnPressed: if (root.enabled) root.clicked()
    Keys.onSpacePressed: if (root.enabled) root.clicked()
}
