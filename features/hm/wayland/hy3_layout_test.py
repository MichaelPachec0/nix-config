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


if __name__ == "__main__":
    unittest.main()
