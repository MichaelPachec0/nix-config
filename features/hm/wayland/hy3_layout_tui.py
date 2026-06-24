#!/usr/bin/env python3
"""hy3-layout-tui: a Textual TUI for building hy3 layouts.

Thin UI over the hy3_layout engine. Pure logic lives in hy3_layout_tui_model
(the editable model + save IO) and hy3_layout_apps (XDG discovery + command
builder); this module owns only the Textual screens.
"""
import logging
import os

from hy3_layout import Group, Window, parse, to_notation
import hy3_layout as engine

import hy3_layout_tui_model as model
import hy3_layout_apps as apps

from textual.app import App, ComposeResult
from textual.screen import ModalScreen
from textual.widgets import Tree, Static, Input, Checkbox, Button, ListView, ListItem, Label
from textual.containers import Vertical, Horizontal
from rich.text import Text


# Opt-in debug log (off unless --log / $HY3_TUI_LOG sets a path). _log.debug is a
# cheap no-op when no handler is attached, so the call sites cost nothing when
# logging is disabled.
_log = logging.getLogger("hy3-layout-tui")


def _default_log_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "hy3-layout", "tui.log")


def _setup_logging(path):
    if not path:
        return
    path = os.path.expanduser(path)
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    for handler in list(_log.handlers):
        _log.removeHandler(handler)
    handler = logging.FileHandler(path)
    handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
    _log.addHandler(handler)
    _log.setLevel(logging.DEBUG)
    _log.propagate = False
    _log.debug("=== hy3-layout-tui logging started ===")


_ORIENTS = ("H", "V", "T")

# Two keymaps. Each is a list of (key, action, label). The standard keymap is
# the original non-modal binding set; the vim keymap is modal (NORMAL: hjkl
# navigates the tree; commands on vim-style keys). Keys are dispatched in
# on_key against the active keymap, so the same physical key (e.g. "s") can mean
# different things per keymap. Two keys are global to both: backslash toggles
# the keymap and "q" quits.
_KEYMAPS = {
    "standard": [
        ("h", "split_h", "split H"),
        ("v", "split_v", "split V"),
        ("t", "split_t", "split T"),
        ("o", "cycle_orient", "orient"),
        ("k", "move_prev", "move up"),
        ("j", "move_next", "move down"),
        ("x", "delete", "delete"),
        ("a", "assign", "assign"),
        ("i", "info", "info"),
        ("b", "build", "build"),
        ("s", "save", "save"),
        ("l", "load", "load"),
        ("e", "export", "export"),
    ],
    "vim": [
        ("h", "nav_parent", "parent"),
        ("j", "nav_down", "down"),
        ("k", "nav_up", "up"),
        ("l", "nav_child", "child"),
        ("s", "split_h", "split H"),
        ("v", "split_v", "split V"),
        ("t", "split_t", "split T"),
        ("J", "move_next", "move down"),
        ("K", "move_prev", "move up"),
        ("o", "cycle_orient", "orient"),
        ("x", "delete", "delete"),
        ("a", "assign", "assign"),
        ("i", "info", "info"),
        ("b", "build", "build"),
        ("w", "save", "save"),
        ("e", "load", "load"),
        ("y", "export", "export"),
    ],
}


def resolve_keymap(name):
    return name if name in _KEYMAPS else "standard"


def _default_save_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "hy3-layout", "layouts.json")


class AppPicker(ModalScreen):
    BINDINGS = [("escape", "cancel", "cancel")]

    def action_cancel(self):
        self.dismiss(None)

    def __init__(self, terminal, discovered=None):
        super().__init__()
        self._terminal = terminal
        self._apps = discovered if discovered is not None else []
        # (name_lower, ListItem) pairs, so the search box can show/hide each item.
        self._items = []

    def compose(self):
        self._items = []
        for a in self._apps:
            item = ListItem(Label(a.name, markup=False), name=a.exec_cmd)
            self._items.append((a.name.lower(), item))
        yield Vertical(
            Label("Type to search apps, or type a command below:"),
            # The search box is the first focusable widget, so it has focus on
            # open -- start typing to filter the list immediately.
            Input(placeholder="search apps", id="search"),
            ListView(*[item for _name, item in self._items], id="apps"),
            Input(placeholder="command", id="cmd"),
            Input(placeholder="args", id="args"),
            Checkbox("Run in terminal", id="term"),
            Input(placeholder="cwd (optional)", id="cwd"),
            Input(id="preview"),
            Button("OK", id="ok"),
            Button("Cancel", id="cancel"),
        )

    def _apply_filter(self, query):
        q = query.strip().lower()
        for name_lower, item in self._items:
            item.display = (q in name_lower) if q else True

    def _spec(self):
        return apps.CommandSpec(
            base=self.query_one("#cmd", Input).value,
            args=self.query_one("#args", Input).value,
            in_terminal=self.query_one("#term", Checkbox).value,
            terminal=self._terminal,
            cwd=self.query_one("#cwd", Input).value or None,
        )

    def _refresh_preview(self):
        if self.query_one("#cmd", Input).value:
            self.query_one("#preview", Input).value = apps.build_command(self._spec())

    def on_list_view_selected(self, event):
        if event.item is not None and event.item.name:
            self.query_one("#cmd", Input).value = event.item.name
            self._refresh_preview()

    def on_input_changed(self, event):
        if event.input.id == "search":
            self._apply_filter(event.value)
        elif event.input.id in ("cmd", "args"):
            self._refresh_preview()

    def on_checkbox_changed(self, event):
        self._refresh_preview()

    def on_button_pressed(self, event):
        if event.button.id == "ok":
            self._accept()
        else:
            self.dismiss(None)

    def _accept(self):
        command = self.query_one("#preview", Input).value or self.query_one("#cmd", Input).value
        cwd = self.query_one("#cwd", Input).value or None
        self.dismiss((command, cwd) if command else None)


class WorkspacePrompt(ModalScreen):
    BINDINGS = [("escape", "cancel", "cancel")]

    def action_cancel(self):
        self.dismiss(None)

    def __init__(self, title):
        super().__init__()
        self._title = title

    def compose(self):
        yield Vertical(
            Label(self._title),
            Input(placeholder="workspace number", id="ws"),
            Button("OK", id="ok"),
            Button("Cancel", id="cancel"),
        )

    def on_button_pressed(self, event):
        if event.button.id != "ok":
            self.dismiss(None)
            return
        raw = self.query_one("#ws", Input).value.strip()
        try:
            self.dismiss(int(raw))
        except ValueError:
            self.dismiss(None)


class CommandLine(ModalScreen):
    # A vim-style ':' command line. Submitting dismisses with the typed string
    # (e.g. "g", "g 3", "q"); the editor parses it. Esc cancels.
    BINDINGS = [("escape", "cancel", "cancel")]

    def action_cancel(self):
        self.dismiss(None)

    def compose(self):
        yield Vertical(
            Label("Command -- g grab, b build, w save, e load "
                  "(N = ws, default active); q quit:"),
            Input(placeholder=":", id="cmdline"),
        )

    def on_input_submitted(self, event):
        self.dismiss(event.value)


def _leaf_label(window):
    if window.command:
        text = window.command
        if window.cwd:
            text += " @" + window.cwd
        return text
    return "<%s>" % window.label


# --- spatial preview: render the layout AST as ASCII boxes --------------------
# ASCII only ('+', '-', '|') so the source stays ASCII and Static markup=False is
# enough. H -> boxes side by side, V -> stacked, T -> a tab strip on the top edge
# with the first child in the body. The selected node's box uses '*' corners.

def _short_label(node):
    return node.kind if isinstance(node, Group) else node.label


def _grid_set(grid, x, y, ch):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = ch


def _grid_text(grid, x, y, text):
    for i, ch in enumerate(text):
        _grid_set(grid, x + i, y, ch)


def _draw_border(grid, x, y, w, h, corner):
    for i in range(w):
        _grid_set(grid, x + i, y, "-")
        _grid_set(grid, x + i, y + h - 1, "-")
    for j in range(h):
        _grid_set(grid, x, y + j, "|")
        _grid_set(grid, x + w - 1, y + j, "|")
    for cx, cy in ((x, y), (x + w - 1, y), (x, y + h - 1), (x + w - 1, y + h - 1)):
        _grid_set(grid, cx, cy, corner)


def _split_sizes(total, n):
    base, rem = divmod(total, n)
    return [base + (1 if i < rem else 0) for i in range(n)]


def _draw_node(grid, node, x, y, w, h, selected):
    if w < 3 or h < 2:
        _grid_text(grid, x, y, _short_label(node)[:max(0, w)])
        return
    corner = "*" if node is selected else "+"
    if isinstance(node, Window):
        _draw_border(grid, x, y, w, h, corner)
        _grid_text(grid, x + 1, y + 1, _leaf_label(node)[:w - 2])
        return
    if node.kind == "T":
        _draw_border(grid, x, y, w, h, corner)
        tabs = "".join("[%s]" % _short_label(c) for c in node.children)
        _grid_text(grid, x + 1, y, tabs[:w - 2])          # tab strip on top edge
        if node.children:
            _draw_node(grid, node.children[0], x + 1, y + 1, w - 2, h - 2, selected)
        return
    if node.kind == "V":
        cy = y
        for child, ch_h in zip(node.children, _split_sizes(h, len(node.children))):
            _draw_node(grid, child, x, cy, w, ch_h, selected)
            cy += ch_h
        return
    # H (and any other group) -> side by side
    cx = x
    for child, cw in zip(node.children, _split_sizes(w, len(node.children))):
        _draw_node(grid, child, cx, y, cw, h, selected)
        cx += cw


def render_layout_ascii(node, width, height, selected=None):
    width = max(width, 4)
    height = max(height, 3)
    grid = [[" "] * width for _ in range(height)]
    _draw_node(grid, node, 0, 0, width, height, selected)
    # Full-width lines (no rstrip): every cell is written on every frame, so the
    # previous frame's characters are always overwritten -- otherwise a shorter
    # line leaves stale glyphs behind when the selection moves.
    return "\n".join("".join(row) for row in grid)


class LayoutEditorApp(App):
    CSS = """
    #body { height: 1fr; }
    #layout { width: 50%; height: 100%; }
    #preview { width: 50%; height: 100%; overflow: hidden; }
    #statusbars { dock: bottom; height: 2; }
    #notation { height: 1; background: $panel; }
    #shortcuts { height: 1; background: $boost; }
    """

    def __init__(self, layout_model=None, keymap="standard"):
        super().__init__()
        self.model = layout_model or model.TuiModel()
        self._rebuilding = False
        self._terminal = apps.default_terminal()
        self.keymap = resolve_keymap(keymap)
        self.mode = "NORMAL"
        self._shortcuts_text = ""
        self._preview_text = ""
        self._notation_text = ""

    def compose(self) -> ComposeResult:
        # Left: the structure tree. Right: a spatial ASCII preview of what the
        # layout would actually look like. markup=False on the Static widgets:
        # the text contains '[' / '=' (e.g. "H[a=kitty, b]", tab strips "[a]")
        # which Textual would otherwise parse as console markup and crash on.
        yield Horizontal(
            Tree("layout", id="layout"),
            Static("", id="preview", markup=False),
            id="body",
        )
        # The two bottom bars MUST share one docked container -- two separate
        # `dock: bottom` widgets overlap on the same row (the status bar would be
        # hidden under the shortcut bar). The Vertical (height 2) stacks them:
        # the notation/status line on top, the shortcut bar below.
        yield Vertical(
            Static("", id="notation", markup=False),
            Static("", id="shortcuts", markup=False),
            id="statusbars",
        )

    def on_mount(self) -> None:
        _log.debug("mount keymap=%s notation=%s", self.keymap, self.model.notation())
        self.rebuild_tree()
        self._render_shortcuts()
        # Focus the tree so its cursor is active/visible and hjkl/arrow motion
        # works immediately.
        self.query_one("#layout", Tree).focus()
        # Render the preview once the layout has settled so it fits the pane.
        self.call_after_refresh(self._render_preview)

    # --- keymap / mode / shortcut bar -------------------------------------
    def _render_shortcuts(self) -> None:
        parts = []
        if self.keymap == "vim":
            parts.append("-- %s --" % self.mode)
        for key, _action, label in _KEYMAPS[self.keymap]:
            parts.append("%s %s" % (key, label))
        parts.append(": cmd")
        parts.append("\\ keymap")
        parts.append("q quit")
        self._shortcuts_text = "  ".join(parts)
        self.query_one("#shortcuts", Static).update(self._shortcuts_text)

    def on_key(self, event) -> None:
        _log.debug("key key=%r char=%r keymap=%s mode=%s stack=%d",
                   event.key, event.character, self.keymap, self.mode,
                   len(self.screen_stack))
        # While a modal (AppPicker / WorkspacePrompt) is open it owns all input
        # -- this is INSERT mode. Do not dispatch editor commands underneath it.
        if len(self.screen_stack) > 1:
            return
        char = event.character
        key = event.key
        # global to both keymaps
        if char == ":":
            self.action_command_line()
            event.stop()
            return
        if char == "\\":
            self.action_toggle_keymap()
            event.stop()
            return
        if char == "q" or key == "q":
            self.exit()
            event.stop()
            return
        table = {k: a for (k, a, _label) in _KEYMAPS[self.keymap]}
        action = table.get(char) or table.get(key)
        if action is not None:
            _log.debug("dispatch action=%s (key=%r keymap=%s)", action, char, self.keymap)
            getattr(self, "action_" + action)()
            event.stop()

    def action_toggle_keymap(self) -> None:
        self.keymap = "vim" if self.keymap == "standard" else "standard"
        self._render_shortcuts()

    def _enter_mode(self, mode: str) -> None:
        self.mode = mode
        self._render_shortcuts()

    # --- vim navigation (NORMAL mode) -------------------------------------
    def action_nav_down(self) -> None:
        self.query_one("#layout", Tree).action_cursor_down()

    def action_nav_up(self) -> None:
        self.query_one("#layout", Tree).action_cursor_up()

    def action_nav_parent(self) -> None:
        parent, _idx = self.model._find_parent(self.model.selected)
        if parent is not None:
            self.model.selected = parent
            self._select_in_tree(parent)

    def action_nav_child(self) -> None:
        sel = self.model.selected
        if isinstance(sel, Group) and sel.children:
            child = sel.children[0]
            self.model.selected = child
            self._select_in_tree(child)

    # --- rendering --------------------------------------------------------
    def rebuild_tree(self) -> None:
        tree = self.query_one("#layout", Tree)
        self._rebuilding = True
        try:
            tree.clear()
            tree.root.data = self.model.root
            # Label the root node with the ACTUAL root container (H/V/T) or the
            # single window -- not a generic "layout" wrapper -- so the root's
            # orientation (e.g. a tab container) is visible at the top.
            tree.root.set_label(Text(self._label_for(self.model.root)))
            self._add_children(tree.root, self.model.root)
            tree.root.expand_all()
            self._select_in_tree(self.model.selected)
        finally:
            self._rebuilding = False
        self._refresh_notation()
        self._render_preview()

    def _label_for(self, node):
        return node.kind if isinstance(node, Group) else _leaf_label(node)

    def _add_children(self, tree_node, layout_node):
        if not isinstance(layout_node, Group):
            return
        for child in layout_node.children:
            # Text() so a command containing '[' is rendered literally, not
            # parsed as console markup.
            child_tree = tree_node.add(Text(self._label_for(child)), data=child)
            self._add_children(child_tree, child)

    def _walk_tree_nodes(self, tree_node):
        yield tree_node
        for child in tree_node.children:
            yield from self._walk_tree_nodes(child)

    def _select_in_tree(self, layout_node):
        tree = self.query_one("#layout", Tree)
        for tree_node in self._walk_tree_nodes(tree.root):
            if tree_node.data is layout_node:
                tree.move_cursor(tree_node)
                return

    def _refresh_notation(self) -> None:
        self._notation_text = self.model.notation()
        self.query_one("#notation", Static).update(self._notation_text)

    def _render_preview(self) -> None:
        pv = self.query_one("#preview", Static)
        # Use the CSS-fixed box size (height:100%), and HARD-CAP it. Never derive
        # the render height from content: an auto-height Static fed its own line
        # count back as its size, so the preview doubled every render
        # (14 -> 28 -> ... -> 28672 lines) and exploded vertically.
        size = pv.size
        width = min(size.width or 48, 400)
        height = min(size.height or 14, 200)
        self._preview_text = render_layout_ascii(
            self.model.root, width, height, self.model.selected)
        # no_wrap + crop: never wrap a too-wide line onto a second row (that is
        # what added stray '|' borders on every j/k). A Text renderable also
        # bypasses console-markup parsing, so '[a]' tab strips are safe.
        pv.update(Text(self._preview_text, no_wrap=True, overflow="crop"))
        if _log.isEnabledFor(logging.DEBUG):
            lines = self._preview_text.split("\n")
            maxlen = max((len(line) for line in lines), default=0)
            _log.debug(
                "render_preview content_size=%sx%s render=%sx%s lines=%d maxlen=%d "
                "wrap_risk=%s notation=%s", size.width, size.height, width, height,
                len(lines), maxlen, maxlen > (size.width or 48),
                self.model.notation())
            _log.debug("preview:\n%s", self._preview_text)

    # --- selection sync ---------------------------------------------------
    def on_tree_node_highlighted(self, event: Tree.NodeHighlighted) -> None:
        if self._rebuilding:
            return
        node = event.node.data
        _log.debug("highlight changed=%s node=%s",
                   node is not None and node is not self.model.selected,
                   _short_label(node) if node is not None else None)
        # Only react to a REAL selection change. Updating the preview Static
        # triggers a relayout that can re-highlight the current node; rendering
        # again on that re-fires the cycle -- a message storm that backs up the
        # queue and eventually FREEZES the UI after enough keypresses. Guarding
        # on an actual change breaks the loop.
        if node is not None and node is not self.model.selected:
            self.model.selected = node
            self._render_preview()      # move the highlight in the preview too

    # --- structural actions -----------------------------------------------
    def _split(self, orient: str) -> None:
        if isinstance(self.model.selected, Window):
            self.model.split(orient)
            self.rebuild_tree()

    def action_split_h(self) -> None:
        self._split("H")

    def action_split_v(self) -> None:
        self._split("V")

    def action_split_t(self) -> None:
        self._split("T")

    def action_cycle_orient(self) -> None:
        if isinstance(self.model.selected, Group):
            current = self.model.selected.kind
            nxt = _ORIENTS[(_ORIENTS.index(current) + 1) % len(_ORIENTS)]
            self.model.set_orient(nxt)
            self.rebuild_tree()

    def action_move_prev(self) -> None:
        self.model.move(-1)
        self.rebuild_tree()

    def action_move_next(self) -> None:
        self.model.move(1)
        self.rebuild_tree()

    def action_delete(self) -> None:
        self.model.delete()
        self.rebuild_tree()

    def action_assign(self) -> None:
        if not isinstance(self.model.selected, Window):
            return

        # Discover apps before pushing the screen so the filesystem scan
        # does not block the Textual message pump (avoids asyncio slow-task
        # warnings in test / debug mode).
        discovered = apps.discover_apps()

        def done(result):
            self._enter_mode("NORMAL")
            if result is not None:
                command, cwd = result
                self.model.assign(command, cwd)
                self.rebuild_tree()

        self._enter_mode("INSERT")
        self.push_screen(AppPicker(self._terminal, discovered), done)

    # --- actions layer ----------------------------------------------------

    def _status(self, text):
        self._notation_text = text
        self.query_one("#notation", Static).update(text)

    def action_info(self) -> None:
        # Show details for the selected node in the status bar (until the next
        # edit refreshes the notation).
        node = self.model.selected
        if isinstance(node, Window):
            info = "window '%s'  command=%s  cwd=%s" % (
                node.label, node.command or "<none>", node.cwd or "<none>")
        else:
            info = "%s group  %d children  %s" % (
                node.kind, len(node.children), to_notation(node))
        self._status(info)

    def build_on(self, ws):
        drawn = parse(self.model.notation())
        try:
            engine.run_build(drawn, ws=ws)
            tree = engine.dump_workspace_tree(ws)
        except Exception as exc:   # surface, never traceback in the UI
            return "build failed: %s" % exc
        built = engine.ast_from_tree(tree)
        if built is not None and engine._same_structure(built, drawn):
            return "verify: ok"
        shown = to_notation(built) if built is not None else "(empty)"
        return "built != drawn: %s" % shown

    def save_to(self, path, ws):
        try:
            model.save_notation(path, ws, self.model.notation())
        except model.SaveFileError as exc:
            return "save failed: %s" % exc
        return "saved ws%s" % ws

    def load_from(self, path, ws):
        try:
            loaded = model.load_model(path, ws)
        except model.SaveFileError as exc:
            return "load failed: %s" % exc
        self.model = loaded
        self.rebuild_tree()
        return "loaded ws%s" % ws

    def grab_from_ws(self, ws):
        # Import the CURRENT (live) layout of a workspace into the editor.
        # Windows arrive as their class (an approximate command, editable before
        # rebuild). Needs a running Hyprland with the dump_tree dispatcher.
        try:
            tree = engine.dump_workspace_tree(ws)
        except Exception as exc:   # surface, never traceback in the UI
            return "grab failed: %s" % exc
        try:
            info = engine.active_addr_info()
        except Exception:
            info = None            # best-effort: structure without commands
        ast = engine.ast_from_tree(tree, info)
        if ast is None:
            return "ws%s is empty" % ws
        self.model = model.TuiModel(ast)
        self.rebuild_tree()
        return "grabbed ws%s" % ws

    def export(self):
        text = self.model.notation()
        self.query_one("#notation", Static).update(text)
        return text

    def action_build(self):
        def done(ws):
            self._enter_mode("NORMAL")
            if ws is not None:
                self._status(self.build_on(ws))
        self._enter_mode("INSERT")
        self.push_screen(WorkspacePrompt("Build on which workspace?"), done)

    def action_save(self):
        path = _default_save_path()

        def done(ws):
            self._enter_mode("NORMAL")
            if ws is not None:
                self._status(self.save_to(path, ws))
        self._enter_mode("INSERT")
        self.push_screen(WorkspacePrompt("Save as which workspace id?"), done)

    def action_load(self):
        path = _default_save_path()

        def done(ws):
            self._enter_mode("NORMAL")
            if ws is not None:
                self._status(self.load_from(path, ws))
        self._enter_mode("INSERT")
        self.push_screen(WorkspacePrompt("Load which workspace id?"), done)

    def action_command_line(self):
        def done(text):
            self._enter_mode("NORMAL")
            if text:
                self._run_command(text)
        self._enter_mode("INSERT")
        self.push_screen(CommandLine(), done)

    def _resolve_ws(self, args):
        # Workspace from the command's first arg, or the active workspace when
        # none is given (':g'/':b'/... with no number -> active ws).
        if args:
            try:
                return int(args[0])
            except ValueError:
                self._status("bad workspace: %r" % args[0])
                return None
        try:
            return engine._active_ws_id()
        except Exception as exc:
            self._status("no active workspace: %s" % exc)
            return None

    def _cmd_save(self, ws):
        return self.save_to(_default_save_path(), ws)

    def _cmd_load(self, ws):
        return self.load_from(_default_save_path(), ws)

    def _run_command(self, text):
        _log.debug("command %r", text)
        parts = text.split()
        if not parts:
            return
        cmd, args = parts[0], parts[1:]
        if cmd in ("q", "quit"):
            self.exit()
            return
        handlers = {
            "g": self.grab_from_ws, "grab": self.grab_from_ws,
            "b": self.build_on, "build": self.build_on,
            "w": self._cmd_save, "write": self._cmd_save,
            "e": self._cmd_load, "edit": self._cmd_load,
        }
        handler = handlers.get(cmd)
        if handler is None:
            self._status("unknown command: %s" % cmd)
            return
        ws = self._resolve_ws(args)
        if ws is not None:
            self._status(handler(ws))

    def action_export(self):
        self.export()


def main(argv=None):
    import argparse
    env_keys = os.environ.get("HY3_TUI_KEYS", "standard")
    ap = argparse.ArgumentParser(prog="hy3-layout-tui")
    ap.add_argument(
        "--keys", choices=["standard", "vim"], default=resolve_keymap(env_keys),
        help="keymap: standard (default) or vim (modal hjkl). Also via "
             "$HY3_TUI_KEYS; toggle live with backslash.")
    ap.add_argument(
        "--log", nargs="?", const=_default_log_path(),
        default=os.environ.get("HY3_TUI_LOG"),
        help="write a debug log to PATH (default: "
             "$XDG_STATE_HOME/hy3-layout/tui.log); also via $HY3_TUI_LOG.")
    args = ap.parse_args(argv)
    _setup_logging(args.log)
    LayoutEditorApp(keymap=args.keys).run()


if __name__ == "__main__":
    main()
