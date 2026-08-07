import QtQuick
// Quickshell's qmlscanner only resolves ONE bare same-directory type per
// document reliably -- see XpDialog.qml's own note. Explicit alias import
// for the same reason.
import "." as Kit

// The header of an XP dialog, in two modes.
//
//   brand = false  a plain Luna title bar: one blue band, title at the
//                  left, subtitle under it. Used by Shut Down and by the
//                  fatal screen.
//
//   brand = true   the Log On to Windows header: a THIN title bar, then a
//                  tall periwinkle brand panel carrying the flag, the
//                  Windows XP wordmark and the copyright, then a warm
//                  separator. This is the composition the real dialog has,
//                  and it is not a taller version of the other one --
//                  putting "Log On to Windows" in large type over a single
//                  blue band (which is what this widget used to do) gets
//                  the structure wrong no matter how accurate the blue is.
//
// title/subtitle are rendered here but not chosen here: LogonDialog.qml
// feeds this from Settings.config.branding, a user-tier writable key, and
// SkinFatal.qml/ShutDownDialog.qml feed fixed literals. Without an explicit
// textFormat, Qt's AutoText detection would let a branding string
// containing markup (including an <img src="file://...">) actually render
// as rich text on a pre-auth screen -- every Text element below pins
// PlainText so that can never happen regardless of which caller drives it.
Item {
    id: root
    required property var theme
    property string title: ""
    property string subtitle: ""
    property bool brand: false
    // Blank by default rather than carrying a hardcoded Microsoft copyright
    // string: this skin is a recreation, and asserting someone else's
    // copyright notice by default would be a false statement rather than a
    // stylistic touch. LogonDialog fills these from branding, so a user who
    // wants the authentic lines can set them.
    property string copyright: ""
    property string edition: ""
    property string wordmark: ""
    property string wordmarkAccent: ""
    property string vendor: ""

    // Absolute path to a banner artwork file. When set, it REPLACES the
    // whole drawn brand panel -- flag, wordmark, copyright and vendor
    // together -- because the real panel is a single bitmap and no amount
    // of type and vector work reproduces it: the wordmark is a custom
    // logotype, the flag is shaded and drop-shadowed, and the panel carries
    // a soft two-axis falloff. Drawing it is the fallback, not the goal.
    //
    // Nix-only by construction. This is a filesystem path rendered into
    // /etc/qs-greeter/defaults.json, and `branding.image` is deliberately
    // NOT one of the fields SettingsMerge.js copies out of the user tier,
    // so a hostile write to the group-writable settings file cannot point
    // this at an arbitrary file and turn a pre-auth screen into a file-read
    // oracle. The drawn strings above stay user-writable because the worst
    // they achieve is wrong text.
    property string image: ""

    // Gated on showFlag as well as on the path being set: showFlag means
    // "this palette is presenting itself as Windows". A palette that turns
    // it off (Gruvbox) must not get the Windows artwork handed to it
    // through a different property.
    readonly property bool usingImage: root.image.length > 0 && theme.showFlag

    // Everything the panel draws for itself is shown only when the artwork
    // is NOT standing in for it -- including when the artwork was asked for
    // but failed to load. A missing or unreadable banner file must degrade
    // to the drawn panel, not to an empty blue rectangle: this is the
    // screen someone logs in through, and it is reached before they can fix
    // anything.
    readonly property bool drawnPanel: !(root.usingImage && art.status === Image.Ready)

    // The artwork's natural width, or 0 when none is in use. Exposed so the
    // dialog can size itself to render the bitmap 1:1 -- this panel is
    // mostly a logotype, and scaling type in a bitmap is exactly the kind of
    // softness that gives away a reproduction. Reads the Image's IMPLICIT
    // width (the file's own dimensions), which does not change when the item
    // is resized, so a consumer binding its width to this cannot loop.
    readonly property int artNaturalWidth:
        (root.usingImage && art.status === Image.Ready) ? art.implicitWidth : 0

    implicitWidth: 400
    // brandPanel.height, not theme.brandPanelHeight: with artwork the panel
    // sizes itself to the file's aspect ratio, so the configured height is
    // only the fallback and the panel is the thing that knows which applies.
    implicitHeight: titleBar.height
        + (root.brand ? brandPanel.height + theme.dividerHeight : 0)
    width: implicitWidth
    height: implicitHeight

    // --- title bar -------------------------------------------------------
    Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // In brand mode this is the real XP title bar height. Without a
        // brand panel it grows to carry the subtitle too.
        height: root.brand ? theme.bannerHeight
                           : Math.max(theme.bannerHeight, titleBlock.implicitHeight + 12)
        gradient: theme.useGradients ? titleGradient : null
        color: theme.useGradients ? "transparent" : theme.bannerMid

        // XP.css themes/XP/_window.scss .title-bar, stop positions kept
        // exactly. The shape is the point: a bright band across the top 8%,
        // a long flat middle, then a step DOWN in the last few percent
        // rather than a fade -- which is what gives Luna's blue its glassy
        // top edge instead of an even ramp.
        Gradient {
            id: titleGradient
            GradientStop { position: 0.0; color: theme.bannerTop }
            GradientStop { position: 0.08; color: theme.bannerUpper }
            GradientStop { position: 0.40; color: theme.bannerMid }
            GradientStop { position: 0.88; color: theme.bannerLower }
            GradientStop { position: 0.93; color: theme.bannerLower }
            GradientStop { position: 0.96; color: theme.bannerFoot }
            GradientStop { position: 1.0; color: theme.bannerFoot }
        }

        Column {
            id: titleBlock
            anchors.left: parent.left
            anchors.leftMargin: theme.rowSpacing
            anchors.right: parent.right
            anchors.rightMargin: theme.dialogPad
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            // XP.css gives .title-bar a 1px/1px text shadow in a deep
            // indigo (theme.bannerShadow). QML Text has no text-shadow
            // property, so the shadow is a second Text one pixel down and
            // right, behind the real one. Without it, white on Luna blue
            // looks flat and slightly too bright.
            Item {
                width: parent.width
                height: titleText.implicitHeight

                Text {
                    x: 1
                    y: 1
                    width: parent.width
                    text: root.title
                    textFormat: Text.PlainText
                    color: theme.bannerShadow
                    font.family: theme.uiBold
                    font.bold: true
                    font.pixelSize: theme.titleSize
                    elide: Text.ElideRight
                }
                Text {
                    id: titleText
                    width: parent.width
                    text: root.title
                    textFormat: Text.PlainText
                    color: theme.bannerText
                    font.family: theme.uiBold
                    font.bold: true
                    font.pixelSize: theme.titleSize
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                visible: !root.brand && root.subtitle.length > 0
                text: root.subtitle
                textFormat: Text.PlainText
                color: theme.bannerSubtext
                font.family: theme.ui
                font.pixelSize: theme.smallSize
                elide: Text.ElideRight
            }
        }
    }

    // --- brand panel -----------------------------------------------------
    Rectangle {
        id: brandPanel
        visible: root.brand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        // With artwork, the panel takes the artwork's own aspect ratio
        // rather than a configured height, so the image is never letterboxed
        // or cropped. Driven off the Image's IMPLICIT size (the file's
        // natural dimensions), not its rendered size -- reading the rendered
        // size here would be a binding loop, since the image fills this very
        // item.
        height: !root.brand
            ? 0
            : (root.usingImage && art.implicitWidth > 0
                ? Math.round(root.width * art.implicitHeight / art.implicitWidth)
                : theme.brandPanelHeight)
        color: theme.brandPanel

        Image {
            id: art
            anchors.fill: parent
            // Explicit file:// URL rather than the bare path. A plain string
            // in `source` is resolved as a URL RELATIVE TO THE DOCUMENT, and
            // this document is loaded through Quickshell's qs: interceptor,
            // so an absolute path can come back out as qs:/nix/store/...
            // instead of a readable file. Building the scheme here removes
            // the question rather than depending on how the path was spelled
            // upstream.
            source: root.usingImage
                ? (root.image.charAt(0) === "/" ? "file://" + root.image : root.image)
                : ""
            visible: root.usingImage && art.status === Image.Ready
            // Stretch, not PreserveAspectFit: the panel above has already
            // been sized to this file's exact aspect ratio, so the two agree
            // and there is nothing to letterbox. smooth covers the small
            // upscale from the artwork's natural width to the dialog's.
            fillMode: Image.Stretch
            smooth: true
            mipmap: true
            cache: true
        }

        // The soft lighter wash toward the upper right. A diagonal linear
        // ramp rather than a radial one: at this size the two are
        // indistinguishable, and this needs no shader or extra element.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: theme.brandPanel }
                GradientStop { position: 0.55; color: theme.brandPanel }
                GradientStop { position: 1.0; color: theme.brandPanelLight }
            }
            opacity: 0.9
            visible: root.drawnPanel
        }

        // Flag and wordmark travel together as one centred group, the way
        // the real panel arranges them -- the flag is not anchored to the
        // panel's left edge, it sits immediately left of the word
        // "Windows".
        Row {
            id: logoRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4
            spacing: theme.rowSpacing
            visible: root.drawnPanel && (root.wordmark.length > 0 || theme.showFlag)

            Kit.XpFlag {
                theme: root.theme
                visible: theme.showFlag
                width: 52
                height: 44
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: root.vendor
                    visible: root.vendor.length > 0
                    textFormat: Text.PlainText
                    color: theme.brandText
                    font.family: theme.ui
                    font.pixelSize: theme.smallSize + 1
                }

                // "Windows" with "xp" set small and raised beside it. Two
                // Texts in a Row rather than one string, because the accent
                // is a different size AND a different color -- which a
                // single PlainText cannot express, and which rich text
                // could but must not (see this file's header).
                Row {
                    spacing: 2
                    Text {
                        text: root.wordmark
                        textFormat: Text.PlainText
                        color: theme.brandText
                        font.family: theme.uiBold
                        font.bold: true
                        font.pixelSize: theme.wordmarkSize
                    }
                    Text {
                        text: root.wordmarkAccent
                        visible: root.wordmarkAccent.length > 0
                        textFormat: Text.PlainText
                        color: theme.brandAccent
                        font.family: theme.uiBold
                        font.bold: true
                        font.pixelSize: theme.wordmarkAccentSize
                        // Raised, not baseline-aligned: the accent sits up
                        // against the cap height of the wordmark.
                        anchors.top: parent.top
                    }
                }

                Text {
                    text: root.edition
                    visible: root.edition.length > 0
                    textFormat: Text.PlainText
                    color: theme.brandText
                    font.family: theme.ui
                    font.pixelSize: theme.editionSize
                    opacity: 0.95
                }
            }
        }

        Text {
            id: copyrightText
            visible: root.drawnPanel && root.copyright.length > 0
            anchors.left: parent.left
            anchors.leftMargin: theme.rowSpacing
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            text: root.copyright
            textFormat: Text.PlainText
            color: theme.brandText
            font.family: theme.ui
            font.pixelSize: theme.smallSize
            lineHeight: 1.15
        }

        Text {
            visible: root.drawnPanel && root.vendor.length > 0
            anchors.right: parent.right
            anchors.rightMargin: theme.rowSpacing
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            text: root.vendor
            textFormat: Text.PlainText
            color: theme.brandText
            font.family: theme.uiBold
            font.bold: true
            font.italic: true
            font.pixelSize: theme.smallSize
        }
    }

    // --- separator -------------------------------------------------------
    // Horizontal, and it begins and ends in the panel's own blue. Sampled
    // across the reference shot: blue at both edges, through a muted tan,
    // to a warm orange peak just left of centre.
    Rectangle {
        id: divider
        visible: root.brand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: brandPanel.bottom
        height: root.brand ? theme.dividerHeight : 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.dividerEdge }
            GradientStop { position: 0.18; color: theme.dividerMid }
            GradientStop { position: 0.49; color: theme.dividerPeak }
            GradientStop { position: 0.80; color: theme.dividerMid }
            GradientStop { position: 1.0; color: theme.dividerEdge }
        }
    }
}
