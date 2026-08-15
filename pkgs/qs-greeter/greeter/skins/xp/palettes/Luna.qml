// Quickshell's QML import resolution treats a quoted import path as a
// directory, even when it ends in ".qml" -- `import "../Theme.qml" as X`
// resolves to "a directory literally named Theme.qml" and fails with "File
// not found", confirmed empirically while wiring up the test harness for
// this file. The working form is a plain relative directory import of the
// parent folder, then the type by name.
import ".." as Base

// Luna is the palette Theme.qml already describes -- its defaults are the
// Luna colors, so this file overrides nothing. It exists anyway so the
// palette list (meta.json's "palettes") has one real file per name, and so
// Task 12's Gruvbox is a sibling override of the same shape rather than a
// special case that only Gruvbox needs a file for.
Base.Theme {
}
