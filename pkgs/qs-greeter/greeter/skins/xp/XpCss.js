// Luna constants transcribed from XP.css.
//
//   Source:    https://github.com/botoxparty/XP.css
//   License:   MIT
//   Copyright: 2020 Adam Hammad, Jordan Scales
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// ---------------------------------------------------------------------
//
// WHY THIS FILE EXISTS SEPARATELY
//
// Everything here is somebody else's work, transcribed. Keeping it in one
// attributed file means the attribution covers the whole file rather than
// being repeated as a comment beside each borrowed value, and it makes the
// boundary auditable: what XP.css says lives here, what this skin decides
// to call it lives in Theme.qml, and the two are one import apart.
//
// Values are grouped by the XP.css file and selector they came from, using
// XP.css's own names where it has them, so any entry can be diffed against
// upstream without a translation step. Gradient stops keep their original
// positions as fractions -- those positions are load-bearing, not
// decorative: the button face breaks at 0.86, which is the single value
// most often guessed wrong when Luna is recreated from memory.
//
// Deliberately NOT transcribed: XP.css's font stack. It sets body text in
// "Pixelated MS Sans Serif" and title bars in Trebuchet MS; this skin uses
// Tahoma throughout, which is what the real Log On to Windows dialog used
// and what winePackages.fonts actually ships (verified with fc-scan).
.pragma library

// themes/XP/_variables.scss -- :root
var VARIABLES = {
    surface: "#ece9d8",
    buttonHighlight: "#ffffff",
    buttonFace: "#dfdfdf",
    buttonShadow: "#808080",
    windowFrame: "#0a0a0a",
    dialogBlue: "#2267cb",
    inputBorderColor: "#789dbc"
};

// themes/XP/_buttons.scss -- button
var BUTTON = {
    border: "#003c74",
    borderRadius: 3,
    fontSize: 11,

    // Resting: linear-gradient(180deg, #fff 0%, #ecebe5 86%, #d8d0c4 100%)
    face: [
        { pos: 0.0, color: "#ffffff" },
        { pos: 0.86, color: "#ecebe5" },
        { pos: 1.0, color: "#d8d0c4" }
    ],

    // :active -- its own curve, NOT the resting ramp reversed.
    // #cdcac3 0%, #e3e3db 8%, #e5e5de 94%, #f2f2f1 100%
    active: [
        { pos: 0.0, color: "#cdcac3" },
        { pos: 0.08, color: "#e3e3db" },
        { pos: 0.94, color: "#e5e5de" },
        { pos: 1.0, color: "#f2f2f1" }
    ],

    // :hover -- four inset box-shadows, warming toward the bottom:
    // inset -1px 1px #fff0cf, inset 1px 2px #fdd889,
    // inset -2px 2px #fbc761, inset 2px -2px #e5a01a
    hoverShadow: ["#fff0cf", "#fdd889", "#fbc761", "#e5a01a"],

    // :focus -- the same construction in blue. This is also what the
    // default (Enter) button wears; XP has no pulsing glow.
    // inset -1px 1px #cee7ff, inset 1px 2px #98b8ea,
    // inset -2px 2px #bcd4f6, inset 1px -1px / 2px -2px #89ade4
    focusShadow: ["#cee7ff", "#98b8ea", "#bcd4f6", "#89ade4"]
};

// themes/XP/_forms.scss
var FORMS = {
    // select, and by extension every text input on the dialog
    selectBorder: "#7f9db9",
    // input[type=text|password|email], select { height: 23px }
    controlHeight: 23
};

// themes/XP/_window.scss
var WINDOW = {
    // .title-bar -- an eight-stop vertical ramp. Two adjacent pairs repeat
    // a color to hold it flat across a span, which is why 0.88/0.93 and
    // 0.96/1.0 share values.
    titleBar: [
        { pos: 0.0, color: "#0997ff" },
        { pos: 0.08, color: "#0053ee" },
        { pos: 0.40, color: "#0050ee" },
        { pos: 0.88, color: "#0066ff" },
        { pos: 0.93, color: "#0066ff" },
        { pos: 0.95, color: "#005bff" },
        { pos: 0.96, color: "#003dd7" },
        { pos: 1.0, color: "#003dd7" }
    ],
    titleBarTextShadow: "#0f1089",
    titleBarHeight: 28,
    titleFontSize: 13,

    // .window -- six inset box-shadows forming the blue frame, listed
    // outermost pair first.
    frameShadow: ["#00138c", "#0831d9", "#001ea0", "#166aee", "#003bda", "#0855dd"],
    frameRadius: 8
};

// Convenience accessors so a consumer never indexes a stop list by number
// (which would silently follow upstream if a stop were ever inserted).
function stopColor(stops, pos) {
    for (var i = 0; i < stops.length; i++) {
        if (stops[i].pos === pos) return stops[i].color;
    }
    return undefined;
}
