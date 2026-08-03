import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Floating "pill" capsule holding a horizontal row of bar widgets. Three looks,
// driven live by the BarStyle singleton:
//   frosted     -> translucent bgPill fill (Hyprland blurs the wallpaper behind
//                  it), hairline ring, soft elevation drop; the fill carries text
//                  legibility, and glyphs get a directional depth drop.
//   ghost       -> transparent fill, hairline ring; wallpaper shows through.
//                  Legibility comes from tight per-glyph shadows (a centered
//                  black halo + a tight directional drop).
//   ghost-glass -> ghost's tight text shadows on a glass fill (frosted's blurred
//                  bgPill) -- the see-through/legible ghost text over frosted
//                  glass instead of raw wallpaper.
// Two orthogonal traits derive the branches:
//   filled      = has a bgPill fill (frosted + ghost-glass); ghost is transparent.
//   frostedText = the fill-carried text treatment (frosted only): soft elevation
//                 outer + directional depth inner. ghost + ghost-glass instead use
//                 the tight ghost shadows (halo inner + tight directional outer).
// Content is declared as children and reparented into the row:
//   Lib.Pill { theme: dock.theme; SomeWidget {} AnotherWidget {} }
Rectangle {
    id: pill

    required property QtObject theme
    property int pad: 10   // inner horizontal padding
    property int gap: 8    // spacing between content items
    // Ring (border) colour; defaults to the shared hairline. Override to accent a
    // specific pill (e.g. the mode pill) without changing any other call site.
    property color ringColor: theme.border
    // Optional alert pulse. When pulseActive is true the WHOLE capsule washes
    // pulseColor with a repeating fade -- because it lives on the pill it fills
    // the entire capsule (full width incl. pad, matching radius) uniformly,
    // instead of a smaller rectangle behind a single widget's content.
    property color pulseColor: "transparent"
    property bool pulseActive: false
    // Idle gap AFTER each flash, before the next one. Settable so a caller
    // cycling several alerts through one pill can group them -- a short gap
    // between the members of a set, a long one after the last. Read when the
    // pause starts, so a handler for `pulsed` can set the next gap in time.
    property int pulseGapMs: 4300
    // Emitted when a flash has fully faded out, before the idle gap. A caller
    // rotating pulseColor advances HERE rather than on its own timer: an
    // independent timer drifts against this cycle and swaps the colour
    // mid-flash, which reads as one stutter instead of two distinct alerts.
    signal pulsed

    readonly property string style: BarStyle.current
    readonly property bool filled: pill.style !== "ghost"
    readonly property bool frostedText: pill.style === "frosted"

    default property alias content: row.data

    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: 30
    // Dynamic-island-style morph: spring the capsule to its new width whenever
    // its content changes size (an app icon opens/closes, a value gains a digit,
    // a CA count changes, a workspace appears) so the bar fluidly reflows instead
    // of snapping. Neighbouring pills glide because the parent RowLayouts read
    // this animating implicitWidth.
    Behavior on implicitWidth {
        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }
    radius: height / 2
    color: pill.filled ? pill.theme.bgPill : "transparent"
    border.width: 1
    border.color: pill.ringColor

    // Outer pass: DROP shadow. frosted = soft straight-down elevation of the glass
    // capsule; ghost / ghost-glass = a tighter down-right drop for the text. Its
    // reach is kept above the inner halo's so nesting never clips it.
    layer.enabled: true
    layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: pill.frostedText ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.85)
        shadowBlur: pill.frostedText ? 0.6 : 0.4
        blurMax: pill.frostedText ? 14 : 10
        shadowVerticalOffset: pill.frostedText ? 4 : 2
        shadowHorizontalOffset: pill.frostedText ? 0 : 2
    }

    // Alert pulse fill: a capsule-shaped wash that fades in/out while pulseActive.
    // Sized to the pill (inset by the ring, radius kept concentric) so the colour
    // covers the whole capsule uniformly. Declared before the content so it sits
    // above the pill fill but behind the glyphs.
    Rectangle {
        id: pulse
        anchors.fill: parent
        anchors.margins: pill.border.width
        radius: pill.radius - pill.border.width
        color: pill.pulseColor
        opacity: 0
        visible: pill.pulseActive || opacity > 0

        // Stepped from a timer, deliberately NOT a SequentialAnimation.
        //
        // Qt's threaded render loop advances the animation driver from the
        // render loop itself, so while ANY animation is running it renders every
        // vblank -- whether or not anything changed. The idle gap below is most
        // of the cycle and changes nothing, but it still rendered: in a frame
        // log of the media marquee (same shape, 1400ms pauses) there were 3 gaps
        // in the 1200-1599ms range across the whole capture, where one per pause
        // would have produced dozens. Median inter-frame gap was 8ms, i.e. 120Hz
        // sustained. An alert can stand for hours, so this pulse held a visible
        // bar at its full refresh rate indefinitely.
        //
        // Stepping opacity touches the scene only during the ~700ms flash and
        // leaves the gap completely idle -- the timer's interval becomes the gap
        // itself, so it wakes once rather than ~130 times. Each property write
        // costs ~2 frames (measured: a second frame is scheduled immediately
        // after the first), so stepMs 33 renders at roughly 60fps while
        // flashing, ~14% of the time, instead of 120fps continuously.
        readonly property int stepMs: 33
        readonly property int riseMs: 220
        readonly property int fallMs: 480
        readonly property real peak: 0.55
        // 0 = fade in, 1 = fade out, 2 = idle gap
        property int phase: 0
        property int elapsed: 0
        // Latched when the gap starts, matching the old PauseAnimation, whose
        // duration was read at pause start (i.e. after pulsed() below).
        property int gapMs: pill.pulseGapMs

        // Easing.OutQuad / Easing.InQuad, matching the animations this replaced.
        function outQuad(t) {
            return 1 - (1 - t) * (1 - t);
        }
        function inQuad(t) {
            return t * t;
        }
        function resetPulse() {
            pulse.phase = 0;
            pulse.elapsed = 0;
            pulse.opacity = 0;
        }

        Timer {
            // In the gap the timer IS the pause: one wake-up, no repaint.
            interval: pulse.phase === 2 ? pulse.gapMs : pulse.stepMs
            repeat: true
            running: pill.pulseActive
            onTriggered: {
                if (pulse.phase === 2) {
                    pulse.phase = 0;
                    pulse.elapsed = 0;
                    return;
                }
                pulse.elapsed += pulse.stepMs;
                if (pulse.phase === 0) {
                    const tIn = Math.min(1, pulse.elapsed / pulse.riseMs);
                    pulse.opacity = pulse.peak * pulse.outQuad(tIn);
                    if (tIn >= 1) {
                        pulse.phase = 1;
                        pulse.elapsed = 0;
                    }
                    return;
                }
                const tOut = Math.min(1, pulse.elapsed / pulse.fallMs);
                pulse.opacity = pulse.peak * (1 - pulse.inQuad(tOut));
                if (tOut >= 1) {
                    pulse.opacity = 0;
                    // Fire AFTER the fade-out, so a caller advancing to the next
                    // alert swaps the colour while the wash is fully transparent.
                    pill.pulsed();
                    pulse.gapMs = pill.pulseGapMs;
                    pulse.phase = 2;
                    pulse.elapsed = 0;
                }
            }
        }
        // Reset when the alert clears mid-flash so no colour is left stranded.
        Connections {
            target: pill
            function onPulseActiveChanged() {
                if (!pill.pulseActive)
                    pulse.resetPulse();
            }
        }
    }

    // Content row. The per-glyph shadow that used to be a SECOND offscreen
    // layer+MultiEffect pass over the content now lives inline on BarText via
    // Text.style, so the pill needs only the single outer capsule-shadow pass.
    Item {
        id: contentWrap
        anchors.fill: parent

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: pill.pad
            spacing: pill.gap
        }
    }
}
