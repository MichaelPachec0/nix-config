// Pure output-selection logic for shell.qml's WlrKeyboardFocus.Exclusive
// claim. No QML imports on purpose, so it is testable headlessly without a
// live compositor -- shell.qml itself, being PanelWindow-rooted, is not
// (see this plan's own note on that limitation). Takes the screens list as
// a plain array of {name} objects rather than reading Quickshell.screens
// directly, the same "pull the decision into pure JS" shape SettingsMerge.js
// already uses for the same testability reason.
.pragma library

// True if `name` names a screen that is actually present in `screens`
// right now.
function isPresent(screens, name) {
    if (!name) return false;
    for (var i = 0; i < screens.length; i++)
        if (screens[i] && screens[i].name === name) return true;
    return false;
}

// True if `screen` is the one screen allowed to hold
// WlrKeyboardFocus.Exclusive: the named primary output when it is
// currently present, else screens[0]. A name that matches nothing
// currently connected (set while docked, then undocked) falls back to the
// screens[0] rule rather than matching nothing at all -- matching nothing
// would leave every window's keyboardFocus at WlrKeyboardFocus.None and
// the whole login surface keyboard-dead, with no error and no crash to
// trip the fallback.
function isPrimary(screens, name, screen) {
    if (!screen) return false;
    if (isPresent(screens, name))
        return screen.name === name;
    return screens.length > 0 && screen === screens[0];
}
