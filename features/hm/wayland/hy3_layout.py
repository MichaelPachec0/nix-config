#!/usr/bin/env python3
"""hy3-layout: compile the hy3 layout notation to and from a live layout.

Phase 1 (this module) is the offline compiler core: parser, AST, planner, IR,
renderers, and the dump_tree -> notation printer back-end. The live executor
(driving hyprctl) and Nix packaging are added in Phase 2.

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


def plan(root):
    ops = []
    for w in leaves(root):
        ops.append(Spawn(w.label, w.command, w.cwd))
    state = {"focus": None}
    _fold(root, ops, state, is_top=True)
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
    lines = []
    row = [op.label for op in ops if isinstance(op, Spawn)]
    lines.append("row: " + " ".join(row))
    for op in ops:
        if not isinstance(op, Fold):
            continue
        parts = []
        if op.focus is not None:
            parts.append("focus " + op.focus)
        parts.extend(["Super+a"] * op.raises)
        if op.wrap:
            parts.append("Super+x")
        else:
            parts.append(_ORIENT_KEYS[op.orient])
        lines.append("; ".join(parts))
    return "\n".join(lines)


_LAYOUT_KIND = {"splith": "H", "splitv": "V", "tabs": "T"}


def notation_from_tree(tree, addr_info=None):
    root = tree.get("root")
    if root is None:
        return ""
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

    return to_notation(conv(root))


def _label_for(i):
    if i < 26:
        return chr(ord("a") + i)
    return "w%d" % i


def main(argv=None):
    import argparse
    import json
    import sys

    ap = argparse.ArgumentParser(prog="hy3-layout")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="compile notation into a layout")
    b.add_argument("notation")
    b.add_argument("--plan", action="store_true", help="print the plan; do not execute")
    b.add_argument("--ws", type=int, default=None)
    b.add_argument("--verify", action="store_true")
    b.add_argument("--browser", default=None)

    s = sub.add_parser("show", help="print a workspace layout as notation")
    s.add_argument("--annotate", action="store_true")
    s.add_argument("--from-file", default=None, help="read a dump_tree JSON file")
    s.add_argument("--wk", default=None)

    sub.add_parser("selftest", help="check the planner against the recipes corpus")

    args = ap.parse_args(argv)

    if args.cmd == "selftest":
        return 0 if run_selftest() else 1

    if args.cmd == "build":
        node = parse(args.notation)
        ops = plan(node)
        if args.plan:
            print(to_notation(node))
            print(render_keybinds(ops))
            return 0
        sys.stderr.write("live build is not implemented in this pass (offline core only)\n")
        return 2

    if args.cmd == "show":
        if args.wk is not None:
            sys.stderr.write(
                "show --wk is deferred: needs the dump_tree workspace-scope patch (0004)\n"
            )
            return 2
        if args.from_file is None:
            sys.stderr.write(
                "live show is not implemented in this pass; pass --from-file <dump_tree.json>\n"
            )
            return 2
        with open(args.from_file) as fh:
            tree = json.load(fh)
        print(notation_from_tree(tree))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
