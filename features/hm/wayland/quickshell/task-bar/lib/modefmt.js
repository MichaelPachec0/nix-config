// Pure helpers for the submap mode indicator. Plain top-level JS so it is both a
// QML JS resource (import "../lib/modefmt.js" as ModeFmt) and readable by the
// Deno test via indirect eval. Do NOT add `.pragma library`.

// Hex codepoint string -> glyph, or "" when there is nothing valid to draw.
// The guard matters: parseInt("zz", 16) is NaN and String.fromCharCode(NaN) is
// U+0000, which paints a garbage box instead of drawing nothing.
function glyphFor(cp) {
    if (cp === null || cp === undefined)
        return "";
    var s = String(cp).trim();
    if (s === "" || !/^[0-9a-fA-F]+$/.test(s))
        return "";
    var n = parseInt(s, 16);
    if (isNaN(n))
        return "";
    return String.fromCharCode(n);
}
