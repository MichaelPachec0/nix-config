import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

import hy3_layout as h


class ParserTest(unittest.TestCase):
    def test_single_window(self):
        self.assertEqual(h.parse("a"), h.Window("a"))

    def test_flat_h_group(self):
        self.assertEqual(
            h.parse("H[a,b]"),
            h.Group("H", [h.Window("a"), h.Window("b")]),
        )

    def test_v_and_t_groups(self):
        self.assertEqual(h.parse("V[a,b]"), h.Group("V", [h.Window("a"), h.Window("b")]))
        self.assertEqual(h.parse("T[a,b]"), h.Group("T", [h.Window("a"), h.Window("b")]))

    def test_nested_and_whitespace(self):
        self.assertEqual(
            h.parse("H[a, V[b, c]]"),
            h.Group("H", [h.Window("a"), h.Group("V", [h.Window("b"), h.Window("c")])]),
        )

    def test_window_label_can_be_group_letter(self):
        # 'H' not followed by '[' is a window label, not a group head
        self.assertEqual(h.parse("T[a, H]"), h.Group("T", [h.Window("a"), h.Window("H")]))

    def test_errors(self):
        with self.assertRaises(h.ParseError):
            h.parse("H[]")            # empty group
        with self.assertRaises(h.ParseError):
            h.parse("H[a,b] junk")    # trailing input
        with self.assertRaises(h.ParseError):
            h.parse("H[a,b")          # unbalanced


class AnnotationTest(unittest.TestCase):
    def test_command(self):
        self.assertEqual(h.parse("c=firefox"), h.Window("c", command="firefox"))

    def test_cwd(self):
        self.assertEqual(h.parse("a@~/proj"), h.Window("a", cwd="~/proj"))

    def test_command_and_cwd(self):
        self.assertEqual(
            h.parse("a=kitty@~/proj"),
            h.Window("a", command="kitty", cwd="~/proj"),
        )

    def test_quoted_command_with_spaces(self):
        self.assertEqual(
            h.parse('c="firefox --new-window"'),
            h.Window("c", command="firefox --new-window"),
        )

    def test_annotation_inside_group(self):
        self.assertEqual(
            h.parse("H[a@/tmp, c=firefox]"),
            h.Group("H", [h.Window("a", cwd="/tmp"), h.Window("c", command="firefox")]),
        )

    def test_unterminated_quote(self):
        with self.assertRaises(h.ParseError):
            h.parse('c="firefox')


class BraceAliasTest(unittest.TestCase):
    def test_braces_parse_as_tab(self):
        self.assertEqual(h.parse("{a,b}"), h.Group("T", [h.Window("a"), h.Window("b")]))

    def test_braces_nested_in_split(self):
        self.assertEqual(
            h.parse("H[a, {b,c}]"),
            h.Group("H", [h.Window("a"), h.Group("T", [h.Window("b"), h.Window("c")])]),
        )


class NotationTest(unittest.TestCase):
    def test_roundtrip_normalizes_braces(self):
        self.assertEqual(h.to_notation(h.parse("H[a, {b,c}]")), "H[a, T[b, c]]")

    def test_roundtrip_annotations(self):
        self.assertEqual(h.to_notation(h.parse("a=kitty@~/proj")), "a=kitty@~/proj")

    def test_quotes_values_with_spaces(self):
        self.assertEqual(
            h.to_notation(h.Window("c", command="firefox --new-window")),
            'c="firefox --new-window"',
        )


class HelpersTest(unittest.TestCase):
    def test_leaves_in_order(self):
        node = h.parse("H[a, V[V[b,c], d]]")
        self.assertEqual([w.label for w in h.leaves(node)], ["a", "b", "c", "d"])

    def test_leftmost_leaf(self):
        node = h.parse("H[a, V[V[b,c], d]]")
        self.assertEqual(h.leftmost_leaf(node), h.Window("a"))
        inner = node.children[1]  # V[V[b,c], d]
        self.assertEqual(h.leftmost_leaf(inner), h.Window("b"))

    def test_leftspine(self):
        self.assertEqual(h.leftspine(h.Window("a")), 0)
        self.assertEqual(h.leftspine(h.parse("V[b,c]")), 1)
        self.assertEqual(h.leftspine(h.parse("V[V[b,c], d]")), 2)
        self.assertEqual(h.leftspine(h.parse("T[H[a,b]]")), 2)


class PlannerTest(unittest.TestCase):
    def test_b1(self):
        # H[a, V[V[b,c], d]] -- top H is realized by root (not folded)
        self.assertEqual(
            h.plan(h.parse("H[a, V[V[b,c], d]]")),
            [
                h.Spawn("a"), h.Spawn("b"), h.Spawn("c"), h.Spawn("d"),
                h.Fold("b", 0, "V"), h.Fold(None, 1, "V"),
            ],
        )

    def test_h1_one_tab(self):
        self.assertEqual(
            h.plan(h.parse("T[ H[a,b], H[c,d] ]")),
            [
                h.Spawn("a"), h.Spawn("b"), h.Spawn("c"), h.Spawn("d"),
                h.Fold("a", 0, "H"), h.Fold("c", 0, "H"), h.Fold("a", 1, "T"),
            ],
        )

    def test_h1_columns_wraps(self):
        self.assertEqual(
            h.plan(h.parse("H[ T[H[a,b]], T[H[c,d]] ]")),
            [
                h.Spawn("a"), h.Spawn("b"), h.Spawn("c"), h.Spawn("d"),
                h.Fold("a", 0, "H"), h.Fold(None, 1, "T", True),
                h.Fold("c", 0, "H"), h.Fold(None, 1, "T", True),
            ],
        )

    def test_spawn_carries_annotations(self):
        self.assertEqual(
            h.plan(h.parse("H[a@/tmp, c=firefox]"))[0],
            h.Spawn("a", None, "/tmp"),
        )


class RenderTest(unittest.TestCase):
    def test_b1_keybinds_match_doc(self):
        recipe = h.render_keybinds(h.plan(h.parse("H[a, V[V[b,c], d]]")))
        self.assertEqual(
            recipe,
            "row: a b c d\n"
            "focus b; Super+Shift+g, l\n"
            "Super+a; Super+Shift+g, l",
        )

    def test_columns_wrap_renders_super_x(self):
        recipe = h.render_keybinds(h.plan(h.parse("H[ T[H[a,b]], T[H[c,d]] ]")))
        self.assertEqual(
            recipe,
            "row: a b c d\n"
            "focus a; Super+Shift+g, Ctrl+l\n"
            "Super+a; Super+x\n"
            "focus c; Super+Shift+g, Ctrl+l\n"
            "Super+a; Super+x",
        )


class SelftestTest(unittest.TestCase):
    def test_every_corpus_entry_matches_plan(self):
        for name, notation, expected in h.CORPUS:
            self.assertEqual(h.plan(h.parse(notation)), expected, name)

    def test_run_selftest_returns_true(self):
        self.assertTrue(h.run_selftest())


def _win(addr):
    return {"node": "window", "address": addr, "hidden": False}


def _grp(layout, *children):
    return {"node": "group", "layout": layout, "hidden": False, "children": list(children)}


class PrinterTest(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(h.notation_from_tree({"workspace": -1, "root": None}), "")

    def test_one_unit_clean(self):
        tree = {"workspace": 1, "root": _grp(
            "root", _grp("tabs", _grp("splith", _win("0x1"), _win("0x2"))))}
        self.assertEqual(h.notation_from_tree(tree), "T[H[a, b]]")

    def test_loose_window_pair(self):
        tree = {"workspace": 1, "root": _grp("root", _grp("splith", _win("0x1"), _win("0x2")))}
        self.assertEqual(h.notation_from_tree(tree), "H[a, b]")

    def test_columns_two_units(self):
        tree = {"workspace": 1, "root": _grp(
            "root",
            _grp("tabs", _grp("splith", _win("0x1"), _win("0x2"))),
            _grp("tabs", _grp("splith", _win("0x3"), _win("0x4"))),
        )}
        self.assertEqual(h.notation_from_tree(tree), "H[T[H[a, b]], T[H[c, d]]]")

    def test_annotate(self):
        tree = {"workspace": 1, "root": _grp("splith", _win("0x1"), _win("0x2"))}
        info = {"0x1": ("kitty", "/tmp"), "0x2": ("firefox", None)}
        self.assertEqual(h.notation_from_tree(tree, info), "H[a=kitty@/tmp, b=firefox]")


class CliTest(unittest.TestCase):
    def test_build_plan_prints_notation_and_recipe(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = h.main(["build", "H[a, {b,c}]", "--plan"])
        out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("H[a, T[b, c]]", out)   # normalized
        self.assertIn("row: a b c", out)

    def test_selftest_subcommand(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = h.main(["selftest"])
        self.assertEqual(rc, 0)
        self.assertIn("corpus layouts ok", buf.getvalue())

    def test_show_from_file(self):
        tree = {"workspace": 1, "root": {
            "node": "group", "layout": "root", "children": [
                {"node": "group", "layout": "splith", "children": [
                    {"node": "window", "address": "0x1"},
                    {"node": "window", "address": "0x2"},
                ]}]}}
        fd, path = tempfile.mkstemp(suffix=".json")
        try:
            with os.fdopen(fd, "w") as fh:
                json.dump(tree, fh)
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show", "--from-file", path])
            self.assertEqual(rc, 0)
            self.assertIn("H[a, b]", buf.getvalue())
        finally:
            os.unlink(path)


class CliLiveShowTest(unittest.TestCase):
    # The live dump seams (dump_active_tree / active_addr_info) are stubbed so
    # these stay offline; the real hyprctl path is exercised by a manual smoke
    # test on a running session.
    def test_show_active_dumps_tree(self):
        tree = {"workspace": 1, "root": _grp(
            "root", _grp("splith", _win("0x1"), _win("0x2")))}
        orig = h.dump_active_tree
        h.dump_active_tree = lambda: tree
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show"])
            self.assertEqual(rc, 0)
            self.assertEqual(buf.getvalue().strip(), "H[a, b]")
        finally:
            h.dump_active_tree = orig

    def test_show_active_annotate(self):
        tree = {"workspace": 1, "root": _grp(
            "root", _grp("splith", _win("0x1"), _win("0x2")))}
        orig_dump, orig_info = h.dump_active_tree, h.active_addr_info
        h.dump_active_tree = lambda: tree
        h.active_addr_info = lambda: {"0x1": ("kitty", None), "0x2": ("firefox", None)}
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show", "--annotate"])
            self.assertEqual(rc, 0)
            self.assertEqual(buf.getvalue().strip(), "H[a=kitty, b=firefox]")
        finally:
            h.dump_active_tree, h.active_addr_info = orig_dump, orig_info

    def test_show_active_failure_returns_2(self):
        def boom():
            raise RuntimeError("no hyprctl")
        orig = h.dump_active_tree
        h.dump_active_tree = boom
        try:
            err = io.StringIO()
            with redirect_stderr(err):
                rc = h.main(["show"])
            self.assertEqual(rc, 2)
            self.assertIn("could not dump active workspace", err.getvalue())
        finally:
            h.dump_active_tree = orig

    def test_show_annotate_failure_returns_2(self):
        tree = {"workspace": 1, "root": _grp(
            "root", _grp("splith", _win("0x1"), _win("0x2")))}
        orig_dump, orig_info = h.dump_active_tree, h.active_addr_info
        h.dump_active_tree = lambda: tree

        def boom():
            raise RuntimeError("no clients")
        h.active_addr_info = boom
        try:
            err = io.StringIO()
            with redirect_stderr(err):
                rc = h.main(["show", "--annotate"])
            self.assertEqual(rc, 2)
            self.assertIn("could not read clients", err.getvalue())
        finally:
            h.dump_active_tree, h.active_addr_info = orig_dump, orig_info


class BuildOpsTest(unittest.TestCase):
    def test_reset_preamble_by_default(self):
        ops = h.build_ops(h.parse("H[a, {b,c}]"))
        self.assertEqual(ops[0], h.Reset())
        self.assertFalse(any(isinstance(o, h.SelectRoot) for o in ops))

    def test_no_reset(self):
        ops = h.build_ops(h.parse("H[a, {b,c}]"), reset=False)
        self.assertFalse(any(isinstance(o, h.Reset) for o in ops))

    def test_append_selects_root_and_folds_top(self):
        # append: SelectRoot preamble, and the top H IS folded (the unit becomes
        # a new root tab), matching hy3-project's verified append sequence
        # (focus b; group tab; focus a; group h).
        ops = h.build_ops(h.parse("H[a, {b,c}]"), append=True)
        self.assertEqual(ops[0], h.Reset())
        self.assertEqual(ops[1], h.SelectRoot())
        folds = [o for o in ops if isinstance(o, h.Fold)]
        self.assertEqual(folds, [h.Fold("b", 0, "T"), h.Fold("a", 0, "H")])

    def test_fresh_no_reset_equals_corpus_plan(self):
        # build_ops without append/reset == the corpus plan() exactly.
        self.assertEqual(
            h.build_ops(h.parse("H[a, V[V[b,c], d]]"), reset=False),
            h.plan(h.parse("H[a, V[V[b,c], d]]")),
        )

    def test_render_includes_preamble(self):
        recipe = h.render_keybinds(h.build_ops(h.parse("H[a, {b,c}]"), append=True))
        lines = recipe.split("\n")
        self.assertTrue(lines[0].startswith("reset:"))
        self.assertIn("select existing root tab", lines[1])
        self.assertIn("row: a b c", recipe)


class CliBuildModesTest(unittest.TestCase):
    def test_build_plan_has_reset_line(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = h.main(["build", "H[a, {b,c}]", "--plan"])
        self.assertEqual(rc, 0)
        self.assertIn("reset:", buf.getvalue())

    def test_build_plan_no_reset(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = h.main(["build", "H[a, {b,c}]", "--plan", "--no-reset"])
        self.assertEqual(rc, 0)
        self.assertNotIn("reset:", buf.getvalue())

    def test_build_plan_append(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = h.main(["build", "H[a, {b,c}]", "--plan", "--append"])
        self.assertEqual(rc, 0)
        self.assertIn("select existing root tab", buf.getvalue())


class CliWkShowTest(unittest.TestCase):
    # --wk N / --wk all consume the 0004 dump_tree(ws) / dump_all dispatchers;
    # the live seams are stubbed so these stay offline.
    def test_show_wk_number(self):
        tree = {"workspace": 3, "root": _grp(
            "root", _grp("splith", _win("0x1"), _win("0x2")))}
        captured = {}

        def fake(ws):
            captured["ws"] = ws
            return tree
        orig = h.dump_workspace_tree
        h.dump_workspace_tree = fake
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show", "--wk", "3"])
            self.assertEqual(rc, 0)
            self.assertEqual(captured["ws"], 3)
            self.assertEqual(buf.getvalue().strip(), "H[a, b]")
        finally:
            h.dump_workspace_tree = orig

    def test_show_wk_all(self):
        trees = [
            {"workspace": 1, "root": _grp("root", _grp("splith", _win("0x1"), _win("0x2")))},
            {"workspace": 2, "root": _grp("root", _grp("splitv", _win("0x3"), _win("0x4")))},
        ]
        orig = h.dump_all_trees
        h.dump_all_trees = lambda: trees
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show", "--wk", "all"])
            self.assertEqual(rc, 0)
            # labels restart per workspace -- each line is a self-contained layout
            self.assertEqual(
                buf.getvalue().strip().split("\n"),
                ["ws1: H[a, b]", "ws2: V[a, b]"],
            )
        finally:
            h.dump_all_trees = orig

    def test_show_wk_all_empty_entry(self):
        orig = h.dump_all_trees
        h.dump_all_trees = lambda: [{"workspace": 5, "root": None}]
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show", "--wk", "all"])
            self.assertEqual(rc, 0)
            self.assertEqual(buf.getvalue().strip(), "ws5: (empty)")
        finally:
            h.dump_all_trees = orig

    def test_show_wk_invalid_returns_2(self):
        err = io.StringIO()
        with redirect_stderr(err):
            rc = h.main(["show", "--wk", "bogus"])
        self.assertEqual(rc, 2)
        self.assertIn("workspace number or 'all'", err.getvalue())

    def test_show_wk_number_failure_returns_2(self):
        def boom(ws):
            raise RuntimeError("no hyprctl")
        orig = h.dump_workspace_tree
        h.dump_workspace_tree = boom
        try:
            err = io.StringIO()
            with redirect_stderr(err):
                rc = h.main(["show", "--wk", "7"])
            self.assertEqual(rc, 2)
            self.assertIn("could not dump workspace 7", err.getvalue())
        finally:
            h.dump_workspace_tree = orig


class RenderTreeTest(unittest.TestCase):
    def test_tree_ascii(self):
        self.assertEqual(
            h.render_tree(h.parse("H[a, {b,c}]")),
            "H\n|- a\n`- T\n   |- b\n   `- c",
        )

    def test_single_window(self):
        self.assertEqual(h.render_tree(h.Window("a")), "a")


class AstFromTreeTest(unittest.TestCase):
    def test_empty_root_is_none(self):
        self.assertIsNone(h.ast_from_tree({"root": None}))
        self.assertIsNone(h.ast_from_tree({"root": _grp("root")}))

    def test_builds_ast(self):
        tree = {"root": _grp("root", _grp("splith", _win("0x1"), _win("0x2")))}
        self.assertEqual(
            h.ast_from_tree(tree),
            h.Group("H", [h.Window("a"), h.Window("b")]),
        )


class ExecutorTest(unittest.TestCase):
    def _trace(self, notation, **kw):
        trace = []
        addrs = iter(["0xA", "0xB", "0xC", "0xD", "0xE", "0xF"])
        saved = (h._spawn_window, h._focus_window, h._hy3_call,
                 h._group_with, h._active_ws_id)

        def spawn(ws, launch):
            trace.append(("spawn", ws, launch))
            return next(addrs)
        h._active_ws_id = lambda: 1
        h._spawn_window = spawn
        h._focus_window = lambda a: trace.append(("focus", a))
        h._hy3_call = lambda fn, arg: trace.append(("hy3", fn, arg))
        h._group_with = lambda d, o: trace.append(("group", d, o))
        try:
            h.run_build(h.parse(notation), **kw)
        finally:
            (h._spawn_window, h._focus_window, h._hy3_call,
             h._group_with, h._active_ws_id) = saved
        return trace

    def test_fresh_build_sequence(self):
        self.assertEqual(self._trace("H[a, {b,c}]"), [
            ("spawn", 1, "kitty"),
            ("focus", "0xA"),
            ("spawn", 1, "kitty"),
            ("focus", "0xB"),
            ("spawn", 1, "kitty"),
            ("focus", "0xB"),
            ("group", "r", "T"),
        ])

    def test_append_sequence(self):
        self.assertEqual(self._trace("H[a, {b,c}]", append=True), [
            ("hy3", "change_focus", "top"),
            ("hy3", "change_focus", "lower"),
            ("spawn", 1, "kitty"),
            ("focus", "0xA"),
            ("spawn", 1, "kitty"),
            ("focus", "0xB"),
            ("spawn", 1, "kitty"),
            ("focus", "0xB"),
            ("group", "r", "T"),
            ("focus", "0xA"),
            ("group", "r", "H"),
        ])

    def test_raise_count_in_fold(self):
        # a nested fold with a raise (top V is folded; not a top-T append-chain)
        trace = self._trace("V[V[a,b], c]")
        self.assertEqual(trace[-2:], [
            ("hy3", "change_focus", "raise"),
            ("group", "r", "V"),
        ])

    def test_group_with_lua_maps_orient(self):
        calls = []
        saved = h._hyprctl
        h._hyprctl = lambda args: calls.append(args) or ""
        try:
            h._group_with("r", "T")
            h._group_with("l", "V")
        finally:
            h._hyprctl = saved
        self.assertEqual(calls, [
            ["eval", 'hl.plugin.hy3.group_with("r", "tab")()'],
            ["eval", 'hl.plugin.hy3.group_with("l", "v")()'],
        ])

    def test_launch_string(self):
        self.assertEqual(h._launch_string(h.Spawn("a"), None), "kitty")
        self.assertEqual(h._launch_string(h.Spawn("c", command="firefox"), None), "firefox")
        self.assertEqual(h._launch_string(h.Spawn("c", command="browser"), "fdev"), "fdev")
        self.assertEqual(
            h._launch_string(h.Spawn("a", cwd="/tmp"), None),
            "sh -c 'cd \"/tmp\" && exec kitty'",
        )

    def test_same_structure(self):
        self.assertTrue(h._same_structure(h.parse("H[a, T[b,c]]"), h.parse("H[x, T[y,z]]")))
        self.assertFalse(h._same_structure(h.parse("H[a, T[b,c]]"), h.parse("H[a, V[b,c]]")))


class CliExecBuildTest(unittest.TestCase):
    def test_build_dispatches_to_run_build(self):
        captured = {}
        saved = h.run_build
        h.run_build = lambda node, **kw: captured.update(kw) or (1, {})
        try:
            rc = h.main(["build", "H[a,b]", "--ws", "8"])
        finally:
            h.run_build = saved
        self.assertEqual(rc, 0)
        self.assertEqual(captured.get("ws"), 8)

    def test_build_visualize_prints_tree_and_builds(self):
        captured = {}
        saved = h.run_build
        h.run_build = lambda node, **kw: captured.setdefault("ran", True) or (1, {})
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["build", "H[a, {b,c}]", "--visualize"])
        finally:
            h.run_build = saved
        self.assertEqual(rc, 0)
        self.assertIn("|- a", buf.getvalue())
        self.assertTrue(captured.get("ran"))

    def test_build_verify_ok(self):
        saved_rb, saved_dt = h.run_build, h.dump_active_tree
        h.run_build = lambda node, **kw: (1, {})
        h.dump_active_tree = lambda: {"workspace": 1, "root": _grp(
            "root", _win("0x1"), _grp("tabs", _win("0x2"), _win("0x3")))}
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["build", "H[a, {b,c}]", "--verify"])
        finally:
            h.run_build, h.dump_active_tree = saved_rb, saved_dt
        self.assertEqual(rc, 0)
        self.assertIn("verify: ok", buf.getvalue())


class CliVisualizeShowTest(unittest.TestCase):
    def test_show_visualize(self):
        tree = {"workspace": 1, "root": _grp(
            "root", _win("0x1"), _grp("tabs", _win("0x2"), _win("0x3")))}
        orig = h.dump_active_tree
        h.dump_active_tree = lambda: tree
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = h.main(["show", "--visualize"])
        finally:
            h.dump_active_tree = orig
        self.assertEqual(rc, 0)
        out = buf.getvalue()
        self.assertIn("H\n", out)
        self.assertIn("`- T", out)


class NaryAppendChainTest(unittest.TestCase):
    def test_build_ops_chains(self):
        # T[a,b,c] -> unit-0 wrapped as a root tab, then SelectRoot+Spawn per unit.
        self.assertEqual(h.build_ops(h.parse("T[a,b,c]")), [
            h.Reset(),
            h.Spawn("a"), h.Fold("a", 0, "T", True),
            h.SelectRoot(), h.Spawn("b"),
            h.SelectRoot(), h.Spawn("c"),
        ])

    def test_two_tabs_also_chain(self):
        # N=2 also append-chains (group_with would leave an implicit splith wrapper).
        self.assertEqual(h.build_ops(h.parse("T[a,b]")), [
            h.Reset(),
            h.Spawn("a"), h.Fold("a", 0, "T", True),
            h.SelectRoot(), h.Spawn("b"),
        ])

    def test_run_build_trace_flat(self):
        trace = []
        addrs = iter(["0xA", "0xB", "0xC", "0xD"])
        saved = (h._spawn_window, h._focus_window, h._hy3_call,
                 h._group_with, h._active_ws_id)
        h._active_ws_id = lambda: 1
        h._spawn_window = lambda ws, launch: (trace.append(("spawn",)), next(addrs))[1]
        h._focus_window = lambda a: trace.append(("focus", a))
        h._hy3_call = lambda fn, arg: trace.append(("hy3", fn, arg))
        h._group_with = lambda d, o: trace.append(("group", d, o))
        try:
            h.run_build(h.parse("T[a,b,c]"))
        finally:
            (h._spawn_window, h._focus_window, h._hy3_call,
             h._group_with, h._active_ws_id) = saved
        self.assertEqual(trace, [
            ("spawn",),
            ("focus", "0xA"), ("hy3", "make_group", "tab"),
            ("hy3", "change_focus", "top"), ("hy3", "change_focus", "lower"),
            ("spawn",),
            ("hy3", "change_focus", "top"), ("hy3", "change_focus", "lower"),
            ("spawn",),
        ])

    def test_render_chained(self):
        recipe = h.render_keybinds(h.build_ops(h.parse("T[a,b,c]")))
        self.assertIn("row: a", recipe)
        self.assertIn("Super+x", recipe)
        self.assertIn("select existing root tab", recipe)
        self.assertIn("row: b", recipe)
        self.assertIn("row: c", recipe)


class SaveRestoreTest(unittest.TestCase):
    def test_parse_wk(self):
        self.assertEqual(h._parse_wk("all"), "all")
        self.assertEqual(h._parse_wk("1,2,3"), [1, 2, 3])
        self.assertEqual(h._parse_wk("5"), [5])
        self.assertIsNone(h._parse_wk("nope"))

    def test_save_writes_annotated_notation(self):
        trees = [
            {"workspace": 1, "root": _grp("root", _grp("splith", _win("0x1"), _win("0x2")))},
            {"workspace": 9, "root": None},  # empty -> skipped
        ]
        info = {"0x1": ("kitty", "/home/michael/proj"), "0x2": ("firefox", None)}
        saved = (h.dump_all_trees, h.active_addr_info)
        h.dump_all_trees = lambda: trees
        h.active_addr_info = lambda: info
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        try:
            out = h.save_layouts("all", path)
            self.assertEqual(out, {"1": "H[a=kitty@/home/michael/proj, b=firefox]"})
            with open(path) as fh:
                self.assertEqual(json.load(fh)["workspaces"], out)
        finally:
            (h.dump_all_trees, h.active_addr_info) = saved
            os.unlink(path)

    def test_save_subset(self):
        trees = [
            {"workspace": 1, "root": _grp("root", _grp("splith", _win("0x1"), _win("0x2")))},
            {"workspace": 2, "root": _grp("root", _grp("splith", _win("0x3"), _win("0x4")))},
        ]
        saved = (h.dump_all_trees, h.active_addr_info)
        h.dump_all_trees = lambda: trees
        h.active_addr_info = lambda: {}
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        try:
            self.assertEqual(list(h.save_layouts([2], path)), ["2"])
        finally:
            (h.dump_all_trees, h.active_addr_info) = saved
            os.unlink(path)

    def test_restore_dispatches_per_ws(self):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as fh:
            json.dump({"version": 1, "workspaces": {"1": "H[a,b]", "2": "T[c,d]"}}, fh)
        calls = []
        saved = (h.run_build, h.dump_workspace_tree, h._active_ws_id, h._focus_workspace)
        h.run_build = lambda node, **kw: calls.append((h.to_notation(node), kw.get("ws")))
        h.dump_workspace_tree = lambda ws: {"workspace": ws, "root": None}  # empty
        h._active_ws_id = lambda: 7
        h._focus_workspace = lambda ws: calls.append(("focus_ws", ws))
        try:
            results = h.restore_layouts("all", path)
        finally:
            (h.run_build, h.dump_workspace_tree, h._active_ws_id, h._focus_workspace) = saved
            os.unlink(path)
        self.assertEqual(calls, [("H[a, b]", 1), ("T[c, d]", 2), ("focus_ws", 7)])
        self.assertTrue(all("restored" in m for _, m in results))

    def test_restore_skips_nonempty(self):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as fh:
            json.dump({"workspaces": {"3": "H[a,b]"}}, fh)
        ran = []
        saved = (h.run_build, h.dump_workspace_tree, h._active_ws_id, h._focus_workspace)
        h.run_build = lambda node, **kw: ran.append(kw.get("ws"))
        h.dump_workspace_tree = lambda ws: {"workspace": ws, "root": _grp("root", _win("0x9"))}
        h._active_ws_id = lambda: 1
        h._focus_workspace = lambda ws: None
        try:
            results = h.restore_layouts("all", path)
        finally:
            (h.run_build, h.dump_workspace_tree, h._active_ws_id, h._focus_workspace) = saved
            os.unlink(path)
        self.assertEqual(ran, [])
        self.assertIn("not empty", results[0][1])


if __name__ == "__main__":
    unittest.main()
