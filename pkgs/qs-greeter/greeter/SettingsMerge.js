// Pure settings merge for the greeter. No QML imports on purpose: this is the
// piece that decides whether a login screen renders at all, so it must be
// testable headlessly.
//
// Trust model: the user tier is a group-writable file. It may carry cosmetic
// keys only. Anything that becomes an argv or loads code (session commands,
// skin paths, logging, auth tuning) is Nix-only, because a hostile write to a
// cosmetic key is an ugly wallpaper while a hostile write to a session argv is
// code execution as the next user to log in.
.pragma library

var SCHEMA_VERSION = 1;

// key -> validator. Presence in this table IS the allow-list.
var COSMETIC = {
    skin: "skin",
    skinSettings: "skinSettings",
    backdrop: "backdrop",
    sessions: "sessions",
    optionsExpanded: "bool",
    rememberLastUser: "bool",
    branding: "branding"
};

// Keys a caller might expect to work but which are deliberately Nix-only.
// Named explicitly so the warning can say "privileged" instead of "unknown".
var PRIVILEGED = [
    "precedence", "skins", "logging", "crashLoop", "auth",
    "userFile", "backdropDir", "group", "package", "enable"
];
var PRIVILEGED_SESSION_KEYS = ["shells", "extra", "filter"];

var BACKDROP_KINDS = ["color", "image"];
var BACKDROP_FITS = ["cover", "contain", "fill", "tile"];

function _clone(o) {
    return JSON.parse(JSON.stringify(o));
}

function _isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function _isBasename(v) {
    return typeof v === "string" && v.length > 0
        && v.indexOf("/") < 0 && v !== "." && v !== "..";
}

function merge(defaults, userText, opts) {
    var out = _clone(defaults);
    var warnings = [];
    var precedence = (opts && opts.precedence) || "user";
    var skins = (opts && opts.skins) || {};

    if (precedence === "nix") return { config: out, warnings: warnings };
    if (userText === null || userText === undefined || userText === "")
        return { config: out, warnings: warnings };

    var user;
    try {
        user = JSON.parse(userText);
    } catch (e) {
        warnings.push("user settings unparseable, ignoring the whole file: " + e);
        return { config: out, warnings: warnings };
    }
    if (!_isObject(user)) {
        warnings.push("user settings not an object, ignoring the whole file");
        return { config: out, warnings: warnings };
    }
    if (user.version !== SCHEMA_VERSION) {
        warnings.push("user settings version " + user.version
            + " != " + SCHEMA_VERSION + ", ignoring the whole file");
        return { config: out, warnings: warnings };
    }

    for (var key in user) {
        if (key === "version") continue;
        if (PRIVILEGED.indexOf(key) >= 0) {
            warnings.push("privileged key '" + key
                + "' in user settings, dropped (set it in Nix)");
            continue;
        }
        if (!COSMETIC.hasOwnProperty(key)) {
            warnings.push("unknown key '" + key + "' in user settings, dropped");
            continue;
        }
        _applyKey(out, key, user[key], skins, warnings);
    }
    return { config: out, warnings: warnings };
}

function _applyKey(out, key, value, skins, warnings) {
    var kind = COSMETIC[key];

    if (kind === "bool") {
        if (typeof value !== "boolean") {
            warnings.push("key '" + key + "' expects a boolean, dropped");
            return;
        }
        out[key] = value;
        return;
    }

    if (kind === "skin") {
        if (typeof value !== "string" || !skins.hasOwnProperty(value)) {
            warnings.push("unregistered skin '" + value + "', dropped");
            return;
        }
        out.skin = value;
        return;
    }

    if (kind === "skinSettings") {
        if (!_isObject(value)) {
            warnings.push("key 'skinSettings' expects an object, dropped");
            return;
        }
        for (var name in value) {
            if (!skins.hasOwnProperty(name)) {
                warnings.push("settings for unregistered skin '" + name + "', dropped");
                continue;
            }
            var sub = value[name];
            if (!_isObject(sub)) {
                warnings.push("skinSettings." + name + " expects an object, dropped");
                continue;
            }
            if (!out.skinSettings) out.skinSettings = {};
            if (!out.skinSettings[name]) out.skinSettings[name] = {};
            if (sub.palette !== undefined) {
                var known = skins[name].palettes || [];
                if (known.indexOf(sub.palette) < 0) {
                    warnings.push("unknown palette '" + sub.palette
                        + "' for skin '" + name + "', dropped");
                } else {
                    out.skinSettings[name].palette = sub.palette;
                }
            }
        }
        return;
    }

    if (kind === "backdrop") {
        if (!_isObject(value)) {
            warnings.push("key 'backdrop' expects an object, dropped");
            return;
        }
        // Validate image before kind: an image kind with a rejected basename
        // must not leave the backdrop pointing at nothing.
        var imageOk = false;
        if (value.image !== undefined) {
            if (value.image === null) {
                out.backdrop.image = null;
            } else if (!_isBasename(value.image)) {
                warnings.push("backdrop.image must be a basename under the "
                    + "backdrop directory, not a path; dropped");
            } else {
                out.backdrop.image = value.image;
                imageOk = true;
            }
        } else if (out.backdrop.image) {
            imageOk = true;
        }
        if (value.kind !== undefined) {
            if (BACKDROP_KINDS.indexOf(value.kind) < 0) {
                warnings.push("backdrop.kind '" + value.kind + "' unknown, dropped");
            } else if (value.kind === "image" && !imageOk) {
                warnings.push("backdrop.kind = image without a usable image, "
                    + "staying on color");
            } else {
                out.backdrop.kind = value.kind;
            }
        }
        if (value.fit !== undefined) {
            if (BACKDROP_FITS.indexOf(value.fit) < 0)
                warnings.push("backdrop.fit '" + value.fit + "' unknown, dropped");
            else out.backdrop.fit = value.fit;
        }
        if (value.color !== undefined) {
            if (typeof value.color !== "string" || !/^#[0-9A-Fa-f]{6}$/.test(value.color))
                warnings.push("backdrop.color must be #RRGGBB, dropped");
            else out.backdrop.color = value.color;
        }
        return;
    }

    if (kind === "sessions") {
        if (!_isObject(value)) {
            warnings.push("key 'sessions' expects an object, dropped");
            return;
        }
        for (var sk in value) {
            if (PRIVILEGED_SESSION_KEYS.indexOf(sk) >= 0) {
                warnings.push("privileged key 'sessions." + sk
                    + "' in user settings, dropped (set it in Nix)");
                continue;
            }
            if (sk === "picker") {
                if (typeof value.picker !== "boolean")
                    warnings.push("sessions.picker expects a boolean, dropped");
                else out.sessions.picker = value.picker;
            } else if (sk === "default") {
                if (value.default !== null && typeof value.default !== "string")
                    warnings.push("sessions.default expects a string, dropped");
                else out.sessions.default = value.default;
            } else {
                warnings.push("unknown key 'sessions." + sk + "', dropped");
            }
        }
        return;
    }

    if (kind === "branding") {
        if (!_isObject(value)) {
            warnings.push("key 'branding' expects an object, dropped");
            return;
        }
        ["title", "subtitle"].forEach(function (f) {
            if (value[f] === undefined) return;
            if (typeof value[f] !== "string")
                warnings.push("branding." + f + " expects a string, dropped");
            else out.branding[f] = value[f];
        });
        return;
    }
}
