#!/usr/bin/env python3
"""XDG .desktop discovery + launch-command building for the hy3-layout TUI.

Pure helpers (no Textual import); stdlib only.

Run the tests with:
    python3 features/hm/wayland/hy3_layout_apps_test.py -v
"""
import configparser
import os
import re
from dataclasses import dataclass
from typing import Optional


@dataclass
class DesktopApp:
    name: str
    exec_cmd: str
    terminal: bool


_FIELD_CODE_RE = re.compile(r"%[fFuUickdDnNvm%]")


def strip_field_codes(exec_value):
    def repl(match):
        return "%" if match.group(0) == "%%" else ""
    return " ".join(_FIELD_CODE_RE.sub(repl, exec_value).split())


def parse_desktop_text(text):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read_string(text)
    except configparser.Error:
        return None
    if not parser.has_section("Desktop Entry"):
        return None
    section = parser["Desktop Entry"]
    if section.get("Type", "Application") != "Application":
        return None
    if section.get("NoDisplay", "false").strip().lower() == "true":
        return None
    if section.get("Hidden", "false").strip().lower() == "true":
        return None
    exec_value = section.get("Exec")
    if not exec_value:
        return None
    name = section.get("Name") or exec_value
    terminal = section.get("Terminal", "false").strip().lower() == "true"
    return DesktopApp(name, strip_field_codes(exec_value), terminal)


def _data_dirs(environ):
    out = []
    home = environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    out.append(home)
    raw = environ.get("XDG_DATA_DIRS")
    if raw is None:
        raw = "/usr/local/share:/usr/share"
    out.extend(part for part in raw.split(":") if part)
    return out


def discover_apps(environ=None):
    environ = os.environ if environ is None else environ
    found = {}   # desktop-file id -> DesktopApp (first data dir wins)
    for directory in _data_dirs(environ):
        appdir = os.path.join(directory, "applications")
        if not os.path.isdir(appdir):
            continue
        for entry in sorted(os.listdir(appdir)):
            if not entry.endswith(".desktop") or entry in found:
                continue
            try:
                with open(os.path.join(appdir, entry)) as handle:
                    app = parse_desktop_text(handle.read())
            except OSError:
                app = None
            if app is not None:
                found[entry] = app
    return sorted(found.values(), key=lambda app: app.name.lower())


@dataclass
class CommandSpec:
    base: str
    args: str = ""
    in_terminal: bool = False
    terminal: str = "kitty"
    cwd: Optional[str] = None   # carried for the picker; flows to model.assign, not into the command string


def build_command(spec):
    inner = spec.base
    if spec.args.strip():
        inner = inner + " " + spec.args.strip()
    if spec.in_terminal:
        return "%s -e %s" % (spec.terminal, inner)
    return inner


def default_terminal(environ=None):
    environ = os.environ if environ is None else environ
    return environ.get("TERMINAL") or "kitty"
