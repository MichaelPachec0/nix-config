#!/usr/bin/env python3
"""hy3-layout: compile the hy3 layout notation to and from a live layout.

Phase 1 (this module) is the offline compiler core: parser, AST, planner, IR,
renderers, and the dump_tree -> notation printer back-end. `show` (active
workspace) drives one live dump_tree call; the live build executor and Nix
packaging are added in Phase 2.

Run the tests with:
    python3 features/hm/wayland/hy3_layout_test.py -v
"""
from dataclasses import dataclass
from typing import Optional


@dataclass
class Window:
    label: str
    command: Optional[str] = None
    cwd: Optional[str] = None


@dataclass
class Group:
    kind: str        # "H", "V", or "T"
    children: list


class ParseError(Exception):
    pass


_GROUP_HEADS = ("H", "V", "T")
_IDENT_CHARS = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
)


def parse(text):
    p = _Parser(text)
    p.skip_ws()
    node = p.parse_node()
    p.skip_ws()
    if not p.at_end():
        raise ParseError("trailing input at %d: %r" % (p.i, text[p.i:]))
    return node


class _Parser:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def at_end(self):
        return self.i >= len(self.s)

    def peek(self):
        return self.s[self.i] if self.i < len(self.s) else ""

    def skip_ws(self):
        while self.i < len(self.s) and self.s[self.i].isspace():
            self.i += 1

    def parse_node(self):
        self.skip_ws()
        c = self.peek()
        if c == "{":
            return self._parse_children("T", "{", "}")
        if c in _GROUP_HEADS and self._group_head_follows():
            kind = c
            self.i += 1
            self.skip_ws()
            return self._parse_children(kind, "[", "]")
        return self._parse_window()

    def _group_head_follows(self):
        j = self.i + 1
        while j < len(self.s) and self.s[j].isspace():
            j += 1
        return j < len(self.s) and self.s[j] == "["

    def _parse_children(self, kind, open_ch, close_ch):
        if self.peek() != open_ch:
            raise ParseError("expected %r at %d" % (open_ch, self.i))
        self.i += 1
        self.skip_ws()
        if self.peek() == close_ch:
            raise ParseError("empty group at %d" % self.i)
        children = []
        while True:
            children.append(self.parse_node())
            self.skip_ws()
            c = self.peek()
            if c == ",":
                self.i += 1
                continue
            if c == close_ch:
                self.i += 1
                break
            raise ParseError(
                "expected ',' or %r at %d: %r" % (close_ch, self.i, self.s[self.i:])
            )
        return Group(kind, children)

    def _parse_window(self):
        label = self._read_ident()
        if not label:
            raise ParseError(
                "expected window label at %d: %r" % (self.i, self.s[self.i:])
            )
        command = None
        cwd = None
        if self.peek() == "=":
            self.i += 1
            command = self._read_value("@,]}")
        if self.peek() == "@":
            self.i += 1
            cwd = self._read_value(",]}")
        return Window(label, command, cwd)

    def _read_value(self, stop):
        c = self.peek()
        if c in ("'", '"'):
            quote = c
            self.i += 1
            start = self.i
            while self.i < len(self.s) and self.s[self.i] != quote:
                self.i += 1
            if self.at_end():
                raise ParseError("unterminated quote at %d" % start)
            val = self.s[start:self.i]
            self.i += 1
            return val
        start = self.i
        while (
            self.i < len(self.s)
            and self.s[self.i] not in stop
            and not self.s[self.i].isspace()
        ):
            self.i += 1
        if self.i == start:
            raise ParseError("expected a value at %d" % self.i)
        return self.s[start:self.i]

    def _read_ident(self):
        start = self.i
        while self.i < len(self.s) and self.s[self.i] in _IDENT_CHARS:
            self.i += 1
        return self.s[start:self.i]


def to_notation(node):
    if isinstance(node, Window):
        s = node.label
        if node.command is not None:
            s += "=" + _quote_value(node.command)
        if node.cwd is not None:
            s += "@" + _quote_value(node.cwd)
        return s
    inner = ", ".join(to_notation(c) for c in node.children)
    return "%s[%s]" % (node.kind, inner)


def _quote_value(v):
    if v == "" or any(ch in v for ch in " ,]}@'\""):
        return '"' + v + '"'
    return v


def leaves(node):
    if isinstance(node, Window):
        return [node]
    out = []
    for c in node.children:
        out.extend(leaves(c))
    return out


def leftmost_leaf(node):
    while isinstance(node, Group):
        node = node.children[0]
    return node


def leftspine(node):
    n = 0
    while isinstance(node, Group):
        n += 1
        node = node.children[0]
    return n


@dataclass
class Spawn:
    label: str
    command: Optional[str] = None
    cwd: Optional[str] = None


@dataclass
class Fold:
    focus: Optional[str]   # window label to focus first, or None to keep focus
    raises: int            # change_focus("raise") count before grouping
    orient: str            # "H", "V", or "T"
    wrap: bool = False     # True = wrap a single child as a tab (no neighbour)


@dataclass
class Reset:
    # Clear any active submap and reset the selection before building, so the
    # fold raise-counts are deterministic regardless of prior workspace state.
    pass


@dataclass
class SelectRoot:
    # Select the existing root tab container (change_focus top, then lower) so
    # the next spawned windows form a new sibling root tab (append mode).
    pass


def plan(root, append=False):
    ops = []
    for w in leaves(root):
        ops.append(Spawn(w.label, w.command, w.cwd))
    state = {"focus": None}
    _fold(root, ops, state, is_top=not append)
    return ops


def build_ops(root, append=False, reset=True):
    # Compose a full executable op list: an optional determinism Reset, an
    # optional SelectRoot (append mode), then the spawn/fold plan. In append
    # mode the layout is folded as a unit (top group included) so it lands as a
    # new root tab beside existing content; a fresh build leaves a top-level H
    # to hy3's H-oriented root.
    #
    # Flat root tabs: building a top-level T by group_with leaves the units under
    # an implicit splith wrapper (root -> splith -> tabs) and NESTS a 3rd+ tab
    # (both verified live). So build a top-level T of >=2 units incrementally:
    # unit-0 wrapped as the first root tab, then an --append pass per remaining
    # unit (each lands as a clean, flat sibling tab).
    if (not append and isinstance(root, Group) and root.kind == "T"
            and len(root.children) >= 2):
        ops = build_ops(Group("T", [root.children[0]]), reset=reset)
        for child in root.children[1:]:
            ops += build_ops(child, append=True, reset=False)
        return ops
    ops = []
    if reset:
        ops.append(Reset())
    if append:
        ops.append(SelectRoot())
    ops.extend(plan(root, append=append))
    return ops


def _fold(node, ops, state, is_top):
    if isinstance(node, Window):
        return
    for c in node.children:
        _fold(c, ops, state, is_top=False)
    if is_top and node.kind == "H":
        return  # hy3's H-oriented root realizes a top-level H; no explicit fold
    _emit(node, ops, state)


def _emit(node, ops, state):
    children = node.children
    c1 = children[0]
    w = leftmost_leaf(c1).label
    focus = None
    if state["focus"] != w:
        focus = w
        state["focus"] = w
    base = leftspine(c1)
    if len(children) == 1:
        ops.append(Fold(focus, base, node.kind, True))
        return
    for k in range(1, len(children)):
        f = focus if k == 1 else None
        ops.append(Fold(f, base + (k - 1), node.kind, False))


# Each entry is hand-derived from docs/hy3-layout-recipes.md by the
# row -> post-order fold -> finish rule. Inner folds match the doc's steps;
# a top-level H is realized by hy3's root (the doc's explicit top-H fold for
# B-1/B-2 is the equivalent, dropped step).
CORPUS = [
    ("B-1", "H[a, V[V[b,c], d]]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Fold("b", 0, "V"), Fold(None, 1, "V"),
    ]),
    ("B-2", "H[a, V[H[b,c], d]]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Fold("b", 0, "H"), Fold(None, 1, "V"),
    ]),
    ("H-1 one-tab", "T[ H[a,b], H[c,d] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Fold("a", 0, "H"), Fold("c", 0, "H"), Fold("a", 1, "T"),
    ]),
    ("H-1 columns", "H[ T[H[a,b]], T[H[c,d]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Fold("a", 0, "H"), Fold(None, 1, "T", True),
        Fold("c", 0, "H"), Fold(None, 1, "T", True),
    ]),
    ("V-1 one-tab", "T[ V[a,b], V[c,d] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Fold("a", 0, "V"), Fold("c", 0, "V"), Fold("a", 1, "T"),
    ]),
    ("H-2 one-tab", "T[ H[a, V[H[b,c], d]], H[e,f] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"), Spawn("e"), Spawn("f"),
        Fold("b", 0, "H"), Fold(None, 1, "V"), Fold("a", 0, "H"),
        Fold("e", 0, "H"), Fold("a", 1, "T"),
    ]),
    ("H-2 columns", "H[ T[H[a, V[H[b,c], d]]], T[H[e,f]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"), Spawn("e"), Spawn("f"),
        Fold("b", 0, "H"), Fold(None, 1, "V"), Fold("a", 0, "H"),
        Fold(None, 1, "T", True),
        Fold("e", 0, "H"), Fold(None, 1, "T", True),
    ]),
    ("H-3 one-tab", "T[ H[T[a,b], T[c,d]], H[e, V[H[f,g], h]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Spawn("e"), Spawn("f"), Spawn("g"), Spawn("h"),
        Fold("a", 0, "T"), Fold("c", 0, "T"), Fold("a", 1, "H"),
        Fold("f", 0, "H"), Fold(None, 1, "V"), Fold("e", 0, "H"),
        Fold("a", 2, "T"),
    ]),
    ("H-3 columns", "H[ T[H[T[a,b], T[c,d]]], T[H[e, V[H[f,g], h]]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Spawn("e"), Spawn("f"), Spawn("g"), Spawn("h"),
        Fold("a", 0, "T"), Fold("c", 0, "T"), Fold("a", 1, "H"),
        Fold(None, 2, "T", True),
        Fold("f", 0, "H"), Fold(None, 1, "V"), Fold("e", 0, "H"),
        Fold(None, 1, "T", True),
    ]),
    ("V-1 columns", "H[ T[V[a,b]], T[V[c,d]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Fold("a", 0, "V"), Fold(None, 1, "T", True),
        Fold("c", 0, "V"), Fold(None, 1, "T", True),
    ]),
    ("V-2 one-tab", "T[ V[a, H[V[b,c], d]], V[e,f] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"), Spawn("e"), Spawn("f"),
        Fold("b", 0, "V"), Fold(None, 1, "H"), Fold("a", 0, "V"),
        Fold("e", 0, "V"), Fold("a", 1, "T"),
    ]),
    ("V-2 columns", "H[ T[V[a, H[V[b,c], d]]], T[V[e,f]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"), Spawn("e"), Spawn("f"),
        Fold("b", 0, "V"), Fold(None, 1, "H"), Fold("a", 0, "V"),
        Fold(None, 1, "T", True),
        Fold("e", 0, "V"), Fold(None, 1, "T", True),
    ]),
    ("V-3 one-tab", "T[ V[T[a,b], T[c,d]], V[e, H[V[f,g], h]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Spawn("e"), Spawn("f"), Spawn("g"), Spawn("h"),
        Fold("a", 0, "T"), Fold("c", 0, "T"), Fold("a", 1, "V"),
        Fold("f", 0, "V"), Fold(None, 1, "H"), Fold("e", 0, "V"),
        Fold("a", 2, "T"),
    ]),
    ("V-3 columns", "H[ T[V[T[a,b], T[c,d]]], T[V[e, H[V[f,g], h]]] ]", [
        Spawn("a"), Spawn("b"), Spawn("c"), Spawn("d"),
        Spawn("e"), Spawn("f"), Spawn("g"), Spawn("h"),
        Fold("a", 0, "T"), Fold("c", 0, "T"), Fold("a", 1, "V"),
        Fold(None, 2, "T", True),
        Fold("f", 0, "V"), Fold(None, 1, "H"), Fold("e", 0, "V"),
        Fold(None, 1, "T", True),
    ]),
]


def run_selftest():
    failures = []
    for name, notation, expected in CORPUS:
        got = plan(parse(notation))
        if got != expected:
            failures.append((name, notation, expected, got))
    for name, notation, _expected, _got in failures:
        print("FAIL %s: %s" % (name, notation))
    print("%d/%d corpus layouts ok" % (len(CORPUS) - len(failures), len(CORPUS)))
    return not failures


_ORIENT_KEYS = {
    "H": "Super+Shift+g, Ctrl+l",
    "V": "Super+Shift+g, l",
    "T": "Super+Shift+g, Shift+l",
}


def render_keybinds(ops):
    # Render ops in order; consecutive Spawns coalesce into one "row:" line. This
    # keeps the recipe correct for append-chained plans (spawns/folds interleave
    # with SelectRoot across units), not just the single-pass case.
    lines = []
    row = []

    def flush_row():
        if row:
            lines.append("row: " + " ".join(row))
            row.clear()

    for op in ops:
        if isinstance(op, Spawn):
            row.append(op.label)
            continue
        flush_row()
        if isinstance(op, Reset):
            lines.append("reset: clear any submap and selection (Escape)")
        elif isinstance(op, SelectRoot):
            lines.append(
                "select existing root tab so new windows form a sibling tab"
                " (change_focus top, then lower)"
            )
        elif isinstance(op, Fold):
            parts = []
            if op.focus is not None:
                parts.append("focus " + op.focus)
            parts.extend(["Super+a"] * op.raises)
            parts.append("Super+x" if op.wrap else _ORIENT_KEYS[op.orient])
            lines.append("; ".join(parts))
    flush_row()
    return "\n".join(lines)


_LAYOUT_KIND = {"splith": "H", "splitv": "V", "tabs": "T"}


def ast_from_tree(tree, addr_info=None):
    # Convert a dump_tree JSON dict to an AST (Window/Group), or None if empty.
    root = tree.get("root")
    if root is None:
        return None
    if root.get("layout") == "root" and not root.get("children"):
        return None
    counter = [0]

    def conv(node):
        if node.get("node") == "window":
            label = _label_for(counter[0])
            counter[0] += 1
            command = None
            cwd = None
            if addr_info is not None:
                info = addr_info.get(node.get("address"))
                if info is not None:
                    command, cwd = info
            return Window(label, command, cwd)
        layout = node.get("layout")
        kids = [conv(ch) for ch in node.get("children", [])]
        if layout == "root":
            return kids[0] if len(kids) == 1 else Group("H", kids)
        kind = _LAYOUT_KIND.get(layout)
        if kind is None:
            raise ValueError("unknown layout %r" % layout)
        return Group(kind, kids)

    return conv(root)


def notation_from_tree(tree, addr_info=None):
    ast = ast_from_tree(tree, addr_info)
    return "" if ast is None else to_notation(ast)


def _label_for(i):
    if i < 26:
        return chr(ord("a") + i)
    return "w%d" % i


def render_tree(node):
    # ASCII tree of a layout AST (groups as H/V/T, windows as their label):
    #   H
    #   |- a
    #   `- T
    #      |- b
    #      `- c
    lines = [_node_label(node)]
    _tree_children(node, "", lines)
    return "\n".join(lines)


def _node_label(node):
    return to_notation(node) if isinstance(node, Window) else node.kind


def _tree_children(node, prefix, lines):
    if not isinstance(node, Group):
        return
    kids = node.children
    for i, child in enumerate(kids):
        last = i == len(kids) - 1
        lines.append(prefix + ("`- " if last else "|- ") + _node_label(child))
        _tree_children(child, prefix + ("   " if last else "|  "), lines)


def _hyprctl(args):
    # Run a hyprctl command and return its stdout. The only live (Hyprland) seam
    # in this module; tests stub dump_active_tree / active_addr_info instead.
    import subprocess
    result = subprocess.run(
        ["hyprctl", *args], capture_output=True, text=True, check=True
    )
    return result.stdout


def _dump_json(lua_fmt):
    # Run a hy3 dump dispatcher that writes JSON to a tempfile and return the
    # parsed result. lua_fmt is a format string with one %s for the (escaped)
    # tempfile path. The live (Hyprland) seam; tests stub the callers below.
    import json
    import os
    import tempfile
    fd, path = tempfile.mkstemp(prefix="hy3-layout-", suffix=".json")
    os.close(fd)
    try:
        lua_path = path.replace("\\", "\\\\").replace('"', '\\"')
        _hyprctl(["eval", lua_fmt % lua_path])
        with open(path) as fh:
            return json.load(fh)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def dump_active_tree():
    # Active workspace tree (0003 dump_tree, no workspace arg).
    return _dump_json('hl.plugin.hy3.dump_tree("%s")()')


def dump_workspace_tree(ws):
    # A specific workspace's tree (0004 dump_tree with a workspace id).
    return _dump_json('hl.plugin.hy3.dump_tree("%%s", %d)()' % int(ws))


def dump_all_trees():
    # Every live workspace's tree as a list (0004 dump_all).
    return _dump_json('hl.plugin.hy3.dump_all("%s")()')


def _proc_children():
    # Map ppid -> [child pids] by scanning /proc once (stdlib, no pgrep).
    import os
    children = {}
    try:
        entries = os.listdir("/proc")
    except OSError:
        return children
    for entry in entries:
        if not entry.isdigit():
            continue
        try:
            with open("/proc/" + entry + "/stat") as fh:
                data = fh.read()
            # stat is "pid (comm) state ppid ..."; comm may contain spaces, so
            # split after the last ')'. ppid is the 2nd field after that.
            ppid = int(data[data.rindex(")") + 1:].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        children.setdefault(ppid, []).append(int(entry))
    return children


def _window_cwd(pid, children):
    # cwd of a window's first child (the shell, for a terminal). kitty keeps its
    # launch cwd, so the child's cwd is the real one. None if unreadable, or just
    # $HOME (uninteresting -> omit so @cwd only shows when it matters).
    import os
    home = os.path.expanduser("~")
    for child in children.get(pid, []):
        try:
            cwd = os.readlink("/proc/%d/cwd" % child)
        except OSError:
            continue
        return None if cwd == home else cwd
    return None


def active_addr_info():
    # Map window address -> (command, cwd) for --annotate / save, from hyprctl
    # clients. command is the window class; cwd is the shell child's working
    # directory (omitted when it is just $HOME). Addresses are session-unique.
    import json
    children = _proc_children()
    info = {}
    for client in json.loads(_hyprctl(["clients", "-j"])):
        addr = client.get("address")
        if not addr:
            continue
        cmd = client.get("class") or None
        pid = client.get("pid")
        cwd = _window_cwd(pid, children) if isinstance(pid, int) and pid > 0 else None
        info[addr] = (cmd, cwd)
    return info


# --- live build executor -------------------------------------------------
# Drives the build_ops IR against Hyprland via the hy3 dispatchers. The small
# helpers below are the live seams; tests stub them to assert the call sequence.

_ORIENT_LETTER = {"H": "h", "V": "v", "T": "tab"}


def _hy3_call(fn, arg):
    # hl.plugin.hy3.<fn>("<arg>")()
    _hyprctl(["eval", 'hl.plugin.hy3.%s("%s")()' % (fn, arg)])


def _group_with(direction, orient):
    # hl.plugin.hy3.group_with("<dir>", "<h|v|tab>")()
    _hyprctl(["eval", 'hl.plugin.hy3.group_with("%s", "%s")()' % (direction, _ORIENT_LETTER[orient])])


def _focus_window(address):
    _hyprctl(["eval", 'hl.dispatch(hl.dsp.focus({ window = "address:%s" }))' % address])


def _active_ws_id():
    import json
    return json.loads(_hyprctl(["activeworkspace", "-j"]))["id"]


def _ws_client_addrs(ws):
    import json
    out = set()
    for client in json.loads(_hyprctl(["clients", "-j"])):
        info = client.get("workspace") or {}
        if info.get("id") == ws and client.get("address"):
            out.add(client["address"])
    return out


def _launch_string(spawn, browser):
    import os
    cmd = spawn.command or "kitty"
    if cmd == "browser":
        cmd = browser or "firefox"
    if spawn.cwd:
        # kitty --directory is dropped through Hyprland's exec, so cd in a shell.
        return "sh -c 'cd \"%s\" && exec %s'" % (os.path.expanduser(spawn.cwd), cmd)
    return cmd


def _spawn_window(ws, launch, timeout=10.0):
    # Spawn onto ws (silent, no view switch) and return the new window address by
    # set-diffing the client list (serialized spawns -> exactly one new address).
    import time
    before = _ws_client_addrs(ws)
    _hyprctl(["eval", "hl.exec_cmd([=[[workspace %d silent] %s]=])" % (ws, launch)])
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        new = _ws_client_addrs(ws) - before
        if new:
            return sorted(new)[0]
        time.sleep(0.1)
    raise RuntimeError("window did not appear within %gs: %s" % (timeout, launch))


def run_build(node, ws=None, append=False, reset=True, browser=None):
    # Execute the build_ops IR live: spawn the row (focusing the previous window
    # so they tile left-to-right), then apply the folds. Returns (ws, labels).
    if ws is None:
        ws = _active_ws_id()
    labels = {}
    last = None
    for op in build_ops(node, append=append, reset=reset):
        if isinstance(op, Reset):
            continue  # scripted execution never enters a submap
        if isinstance(op, SelectRoot):
            _hy3_call("change_focus", "top")
            _hy3_call("change_focus", "lower")
            last = None  # next spawn forms a new root tab, not relative to the prior unit
        elif isinstance(op, Spawn):
            if last is not None:
                _focus_window(labels[last])
            labels[op.label] = _spawn_window(ws, _launch_string(op, browser))
            last = op.label
        elif isinstance(op, Fold):
            if op.focus is not None:
                _focus_window(labels[op.focus])
            for _ in range(op.raises):
                _hy3_call("change_focus", "raise")
            if op.wrap:
                _hy3_call("make_group", "tab")
            else:
                _group_with("r", op.orient)
    return ws, labels


def _same_structure(x, y):
    # Structural AST isomorphism, ignoring window labels/commands.
    if isinstance(x, Window) and isinstance(y, Window):
        return True
    if isinstance(x, Group) and isinstance(y, Group):
        return (x.kind == y.kind and len(x.children) == len(y.children)
                and all(_same_structure(a, b) for a, b in zip(x.children, y.children)))
    return False


# --- save / restore ------------------------------------------------------

def _parse_wk(arg):
    # "all" -> "all"; "1" / "1,2,3" -> [ints]; invalid -> None.
    if arg == "all":
        return "all"
    try:
        return [int(x) for x in arg.split(",") if x.strip() != ""]
    except ValueError:
        return None


def _save_path(file_arg):
    import os
    if file_arg:
        return os.path.expanduser(file_arg)
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "hy3-layout", "layouts.json")


def _focus_workspace(ws):
    _hyprctl(["eval", "hl.dispatch(hl.dsp.focus({ workspace = %d }))" % ws])


def _ws_nonempty(ws):
    return ast_from_tree(dump_workspace_tree(ws)) is not None


def save_layouts(wk, path):
    # Capture selected workspaces as annotated notation; write {ws: notation} as
    # JSON. Returns the {ws: notation} map written.
    import json
    import os
    info = active_addr_info()
    selected = None if wk == "all" else set(wk)
    out = {}
    for entry in dump_all_trees():
        ws = entry.get("workspace")
        if selected is not None and ws not in selected:
            continue
        ast = ast_from_tree(entry, info)
        if ast is not None:
            out[str(ws)] = to_notation(ast)
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "w") as fh:
        json.dump({"version": 1, "workspaces": out}, fh, indent=2)
        fh.write("\n")
    return out


def restore_layouts(wk, path, force=False):
    # Rebuild saved workspaces with the live executor, skipping non-empty ones
    # unless force. Restores the prior active workspace at the end. Returns
    # [(ws, message)].
    import json
    with open(path) as fh:
        saved = json.load(fh).get("workspaces", {})
    targets = sorted(int(k) for k in saved) if wk == "all" else wk
    original = _active_ws_id()
    results = []
    for ws in targets:
        notation = saved.get(str(ws))
        if notation is None:
            results.append((ws, "skipped: not in save file"))
        elif not force and _ws_nonempty(ws):
            results.append((ws, "skipped: workspace not empty (use --force)"))
        else:
            run_build(parse(notation), ws=ws)
            results.append((ws, "restored: " + notation))
    _focus_workspace(original)
    return results


def main(argv=None):
    import argparse
    import json
    import sys

    ap = argparse.ArgumentParser(prog="hy3-layout")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="compile notation into a layout")
    b.add_argument("notation")
    b.add_argument("--plan", action="store_true", help="print the plan; do not execute")
    b.add_argument("--append", action="store_true",
                   help="append the layout as a new root tab to existing workspace content")
    b.add_argument("--no-reset", dest="reset", action="store_false",
                   help="omit the determinism reset preamble")
    b.add_argument("--ws", type=int, default=None)
    b.add_argument("--verify", action="store_true")
    b.add_argument("--browser", default=None)
    b.add_argument("--visualize", action="store_true", help="print an ASCII tree of the layout")

    s = sub.add_parser("show", help="print a workspace layout as notation")
    s.add_argument("--annotate", action="store_true")
    s.add_argument("--from-file", default=None, help="read a dump_tree JSON file")
    s.add_argument("--wk", default=None)
    s.add_argument("--visualize", action="store_true",
                   help="print an ASCII tree instead of one-line notation")

    sub.add_parser("selftest", help="check the planner against the recipes corpus")

    sv = sub.add_parser("save", help="save workspace layouts (annotated) to a file")
    sv.add_argument("--wk", default="all", help="all | N | comma-separated list")
    sv.add_argument("file", nargs="?", default=None,
                    help="output path (default: $XDG_STATE_HOME/hy3-layout/layouts.json)")

    rs = sub.add_parser("restore", help="rebuild saved workspace layouts from a file")
    rs.add_argument("--wk", default="all", help="all | N | comma-separated list")
    rs.add_argument("--force", action="store_true",
                    help="restore even onto a non-empty workspace")
    rs.add_argument("file", nargs="?", default=None,
                    help="input path (default: $XDG_STATE_HOME/hy3-layout/layouts.json)")

    args = ap.parse_args(argv)

    if args.cmd == "selftest":
        return 0 if run_selftest() else 1

    if args.cmd == "build":
        node = parse(args.notation)
        if args.visualize:
            print(render_tree(node))
        if args.plan:
            ops = build_ops(node, append=args.append, reset=args.reset)
            print(to_notation(node))
            print(render_keybinds(ops))
            return 0
        try:
            run_build(node, ws=args.ws, append=args.append, reset=args.reset,
                      browser=args.browser)
        except Exception as e:  # CLI boundary: surface, do not traceback
            sys.stderr.write("error: build failed: %s\n" % e)
            return 2
        if args.verify:
            try:
                tree = dump_active_tree()
            except Exception as e:  # CLI boundary: surface, do not traceback
                sys.stderr.write("error: verify dump failed: %s\n" % e)
                return 2
            got = ast_from_tree(tree)
            if got is not None and _same_structure(got, node):
                print("verify: ok")
                return 0
            sys.stderr.write(
                "verify: structure mismatch (built %s)\n"
                % (to_notation(got) if got is not None else "(empty)")
            )
            return 1
        return 0

    if args.cmd == "show":
        # --annotate info (window class per address) is the same live source for
        # any non-file dump; fetch it once up front.
        info = None
        if args.annotate:
            try:
                info = active_addr_info()
            except Exception as e:  # CLI boundary: surface, do not traceback
                sys.stderr.write("error: could not read clients for --annotate: %s\n" % e)
                return 2

        if args.wk == "all":
            try:
                trees = dump_all_trees()
            except Exception as e:  # CLI boundary: surface, do not traceback
                sys.stderr.write("error: could not dump workspaces: %s\n" % e)
                return 2
            for entry in trees:
                ast = ast_from_tree(entry, info)
                if args.visualize:
                    print("ws%s:" % entry.get("workspace"))
                    print(render_tree(ast) if ast is not None else "(empty)")
                else:
                    print("ws%s: %s" % (entry.get("workspace"),
                                        to_notation(ast) if ast is not None else "(empty)"))
            return 0

        # single source -> one `tree`
        if args.wk is not None:
            try:
                ws_id = int(args.wk)
            except ValueError:
                sys.stderr.write("error: --wk must be a workspace number or 'all'\n")
                return 2
            try:
                tree = dump_workspace_tree(ws_id)
            except Exception as e:  # CLI boundary: surface, do not traceback
                sys.stderr.write("error: could not dump workspace %d: %s\n" % (ws_id, e))
                return 2
        elif args.from_file is not None:
            with open(args.from_file) as fh:
                tree = json.load(fh)
        else:
            try:
                tree = dump_active_tree()
            except Exception as e:  # CLI boundary: surface, do not traceback
                sys.stderr.write("error: could not dump active workspace: %s\n" % e)
                return 2

        ast = ast_from_tree(tree, info)
        if args.visualize:
            print(render_tree(ast) if ast is not None else "(empty)")
        else:
            print(to_notation(ast) if ast is not None else "")
        return 0

    if args.cmd == "save":
        wk = _parse_wk(args.wk)
        if wk is None:
            sys.stderr.write("error: --wk must be a workspace number, list, or 'all'\n")
            return 2
        path = _save_path(args.file)
        try:
            out = save_layouts(wk, path)
        except Exception as e:  # CLI boundary: surface, do not traceback
            sys.stderr.write("error: save failed: %s\n" % e)
            return 2
        print("saved %d workspace(s) to %s" % (len(out), path))
        for ws in sorted(out, key=int):
            print("  ws%s: %s" % (ws, out[ws]))
        return 0

    if args.cmd == "restore":
        wk = _parse_wk(args.wk)
        if wk is None:
            sys.stderr.write("error: --wk must be a workspace number, list, or 'all'\n")
            return 2
        path = _save_path(args.file)
        try:
            results = restore_layouts(wk, path, force=args.force)
        except Exception as e:  # CLI boundary: surface, do not traceback
            sys.stderr.write("error: restore failed: %s\n" % e)
            return 2
        for ws, msg in results:
            print("ws%s: %s" % (ws, msg))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
