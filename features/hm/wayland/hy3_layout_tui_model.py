#!/usr/bin/env python3
"""Editable layout model for the hy3-layout TUI (pure; no Textual import).

Wraps the hy3_layout engine AST (Window/Group) with a selection pointer and
pure mutation ops, plus defensive load/save of the save-restore JSON file.

Run the tests with:
    python3 features/hm/wayland/hy3_layout_tui_model_test.py -v
"""
import json
import os

import hy3_layout as engine
from hy3_layout import Group, Window, to_notation, ParseError, parse


def label_at(i):
    # 0->"a" .. 25->"z", 26->"aa", 27->"ab", ... (stable, unique per index)
    s = ""
    i += 1
    while i > 0:
        i, r = divmod(i - 1, 26)
        s = chr(ord("a") + r) + s
    return s


class TuiModel:
    def __init__(self, root=None):
        self.root = root if root is not None else Window("a")
        self.selected = self.root

    def notation(self):
        return to_notation(self.root)

    def _fresh_label(self):
        used = {w.label for w in engine.leaves(self.root)}
        i = 0
        while label_at(i) in used:
            i += 1
        return label_at(i)

    def _find_parent(self, target):
        # (parent_group, index) for target, or (None, None) if it is the root.
        stack = [self.root]
        while stack:
            node = stack.pop()
            if isinstance(node, Group):
                for i, child in enumerate(node.children):
                    if child is target:
                        return node, i
                    stack.append(child)
        return None, None

    def split(self, orient):
        if not isinstance(self.selected, Window):
            raise ValueError("split: a leaf must be selected")
        leaf = self.selected
        fresh = Window(self._fresh_label())
        group = Group(orient, [leaf, fresh])
        parent, idx = self._find_parent(leaf)
        if parent is None:
            self.root = group
        else:
            parent.children[idx] = group
        self.selected = fresh
        return self.selected

    def set_orient(self, orient):
        if not isinstance(self.selected, Group):
            raise ValueError("set_orient: a group must be selected")
        self.selected.kind = orient
        return self.selected

    def assign(self, command, cwd=None):
        if not isinstance(self.selected, Window):
            raise ValueError("assign: a leaf must be selected")
        self.selected.command = command or None
        self.selected.cwd = cwd or None
        return self.selected

    def move(self, delta):
        parent, idx = self._find_parent(self.selected)
        if parent is None:
            return self.selected
        j = idx + delta
        if 0 <= j < len(parent.children):
            parent.children[idx], parent.children[j] = (
                parent.children[j], parent.children[idx])
        return self.selected

    def delete(self):
        target = self.selected
        parent, idx = self._find_parent(target)
        if parent is None:
            self.root = Window("a")
            self.selected = self.root
            return self.selected
        del parent.children[idx]
        if len(parent.children) == 1:
            sole = parent.children[0]
            grand, gidx = self._find_parent(parent)
            if grand is None:
                self.root = sole
            else:
                grand.children[gidx] = sole
            self.selected = sole
        else:
            self.selected = parent.children[min(idx, len(parent.children) - 1)]
        return self.selected


class SaveFileError(Exception):
    pass


def validate_save_data(data):
    if not isinstance(data, dict):
        raise SaveFileError("unexpected save-file shape (top level is not an object)")
    if not isinstance(data.get("version"), int):
        raise SaveFileError("unexpected save-file shape (missing integer 'version')")
    workspaces = data.get("workspaces")
    if not isinstance(workspaces, dict):
        raise SaveFileError("unexpected save-file shape (missing object 'workspaces')")
    for key, value in workspaces.items():
        if not isinstance(value, str):
            raise SaveFileError("workspace %r entry is not a string" % key)
    return data


def parse_save_text(text):
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise SaveFileError("save file is not valid JSON: %s" % exc)
    return validate_save_data(data)


def model_from_save_data(data, ws_id):
    key = str(ws_id)
    workspaces = data.get("workspaces")
    if not isinstance(workspaces, dict):
        raise SaveFileError("save data missing 'workspaces' object")
    if key not in workspaces:
        raise SaveFileError("no layout saved for ws%s" % key)
    notation = workspaces[key]
    try:
        ast = parse(notation)
    except ParseError as exc:
        raise SaveFileError("ws%s: invalid notation: %s" % (key, exc))
    if parse(to_notation(ast)) != ast:
        raise SaveFileError("ws%s: notation does not round-trip" % key)
    return TuiModel(ast)


def load_model(path, ws_id):
    try:
        with open(path) as handle:
            text = handle.read()
    except FileNotFoundError:
        raise SaveFileError("save file not found: %s" % path)
    except OSError as exc:
        raise SaveFileError("save file could not be read: %s" % exc)
    return model_from_save_data(parse_save_text(text), ws_id)


def save_notation(path, ws_id, notation):
    try:
        existing = None
        if os.path.exists(path):
            with open(path) as handle:
                existing = handle.read()
    except OSError as exc:
        raise SaveFileError("save file could not be read: %s" % exc)
    # parse_save_text raises SaveFileError on a corrupt file -> refuse to clobber.
    data = parse_save_text(existing) if existing is not None else {"version": 1, "workspaces": {}}
    data["workspaces"][str(ws_id)] = notation
    try:
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(path, "w") as handle:
            json.dump(data, handle, indent=2)
            handle.write("\n")
    except OSError as exc:
        raise SaveFileError("save file could not be written: %s" % exc)
    return data
