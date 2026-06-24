import logging
import unittest

from textual.widgets import Input, Static

from hy3_layout_tui import LayoutEditorApp, render_layout_ascii

# Suppress asyncio slow-task debug warnings (IsolatedAsyncioTestCase enables
# asyncio debug mode with a 0.1s threshold; the AppPicker modal compose cycle
# can exceed that in slower environments).
logging.getLogger("asyncio").setLevel(logging.ERROR)


class EditorSkeletonTest(unittest.IsolatedAsyncioTestCase):
    async def test_split_horizontal_updates_notation(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.press("h")
            self.assertEqual(app.model.notation(), "H[a, b]")

    async def test_split_then_vertical_nests(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.press("h")
            await pilot.press("v")
            self.assertEqual(app.model.notation(), "H[a, V[b, c]]")

    async def test_delete_collapses(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.press("h")     # H[a, b], selected b
            await pilot.press("x")     # delete b -> a
            self.assertEqual(app.model.notation(), "a")

    async def test_annotated_notation_does_not_markup_crash(self):
        from hy3_layout import Group, Window
        from hy3_layout_tui_model import TuiModel
        layout = TuiModel(Group("H", [Window("a", "kitty"), Window("b")]))
        app = LayoutEditorApp(layout_model=layout)
        async with app.run_test():
            # on_mount -> rebuild_tree -> _refresh_notation sets the status bar
            # to "H[a=kitty, b]"; the '[' + '=' must NOT be parsed as console
            # markup (regression: Static.update raised MarkupError).
            self.assertEqual(app.model.notation(), "H[a=kitty, b]")

    async def test_status_and_shortcut_bars_do_not_overlap(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.pause()
            notation = app.query_one("#notation", Static).region
            shortcuts = app.query_one("#shortcuts", Static).region
            body = app.query_one("#body").region
            # distinct rows (regression: two dock:bottom bars overlapped, hiding
            # the status bar), and the body ends at/above the status row.
            self.assertEqual(shortcuts.y, notation.y + 1)
            self.assertLessEqual(body.y + body.height, notation.y)

    async def test_info_shows_selected_window_details(self):
        from hy3_layout import Window
        from hy3_layout_tui_model import TuiModel
        app = LayoutEditorApp(layout_model=TuiModel(Window("a", "firefox", "/tmp")))
        async with app.run_test() as pilot:
            await pilot.press("i")                  # info on the selected window
            await pilot.pause()
            self.assertIn("firefox", app._notation_text)
            self.assertIn("/tmp", app._notation_text)

    async def test_info_shows_selected_group_details(self):
        from hy3_layout import Group, Window
        from hy3_layout_tui_model import TuiModel
        app = LayoutEditorApp(
            layout_model=TuiModel(Group("T", [Window("a"), Window("b")])))
        async with app.run_test() as pilot:
            await pilot.press("i")                  # root T group is selected
            await pilot.pause()
            self.assertIn("T group", app._notation_text)
            self.assertIn("2 children", app._notation_text)

    async def test_preview_pane_shows_layout(self):
        from hy3_layout import Group, Window
        from hy3_layout_tui_model import TuiModel
        layout = TuiModel(Group("H", [Window("a", "firefox"), Window("b")]))
        app = LayoutEditorApp(layout_model=layout)
        async with app.run_test() as pilot:
            await pilot.pause()
            self.assertIn("+", app._preview_text)         # ASCII box border
            self.assertIn("firefox", app._preview_text)    # leaf command rendered

    async def test_preview_height_is_stable_across_renders(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.pause()
            first = len(app._preview_text.split("\n"))
            for _ in range(6):
                app._render_preview()
                await pilot.pause()
            last = len(app._preview_text.split("\n"))
            # the rendered line count must NOT grow across renders (regression:
            # an auto-height preview doubled its height every render until it
            # exploded -- 14 -> 28 -> ... -> 28672 lines).
            self.assertEqual(first, last)
            self.assertLess(last, 100)

    async def test_tree_root_shows_root_container_kind(self):
        from hy3_layout import Group, Window
        from hy3_layout_tui_model import TuiModel
        from textual.widgets import Tree
        layout = TuiModel(Group("T", [Window("a"), Window("b")]))
        app = LayoutEditorApp(layout_model=layout)
        async with app.run_test():
            tree = app.query_one("#layout", Tree)
            # the root node shows the actual container (T), not "layout"
            self.assertEqual(str(tree.root.label), "T")

    async def test_shortcut_bar_present_and_shows_standard_keymap(self):
        app = LayoutEditorApp()
        async with app.run_test():
            bar = app.query_one("#shortcuts", Static)    # raises if the bar is absent
            notation = app.query_one("#notation", Static)
            # the shortcut bar sits at the very bottom, at or below the status bar
            self.assertGreaterEqual(bar.region.y, notation.region.y)
            text = app._shortcuts_text
            for token in ("split H", "save", "build", "export", "\\ keymap", "q quit"):
                self.assertIn(token, text)
            # standard keymap is non-modal: no NORMAL/INSERT indicator
            self.assertNotIn("NORMAL", text)


class AppPickerTest(unittest.IsolatedAsyncioTestCase):
    async def test_assign_typed_command_to_leaf(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.press("a")                  # open picker
            picker = app.screen
            picker.query_one("#cmd", Input).value = "kitty"
            picker.query_one("#preview", Input).value = "kitty"
            picker._accept()                        # confirm
            await pilot.pause()
            self.assertEqual(app.model.notation(), "a=kitty")

    async def test_search_filters_app_list(self):
        import hy3_layout_apps as apps_mod
        from hy3_layout_apps import DesktopApp
        original = apps_mod.discover_apps
        apps_mod.discover_apps = lambda: [
            DesktopApp("Firefox", "firefox", False),
            DesktopApp("Kitty", "kitty", False),
            DesktopApp("Nautilus Files", "nautilus", False),
        ]
        try:
            app = LayoutEditorApp()
            async with app.run_test() as pilot:
                await pilot.press("a")                  # open picker
                picker = app.screen
                picker.query_one("#search", Input).value = "fire"
                await pilot.pause()
                shown = [name for name, item in picker._items if item.display]
                self.assertEqual(shown, ["firefox"])    # only Firefox matches "fire"
                picker.query_one("#search", Input).value = ""    # clear restores all
                await pilot.pause()
                shown_all = [name for name, item in picker._items if item.display]
                self.assertEqual(len(shown_all), 3)
        finally:
            apps_mod.discover_apps = original


import hy3_layout as engine
from hy3_layout import Group, Window


class VimKeymapTest(unittest.IsolatedAsyncioTestCase):
    async def test_vim_split_uses_s_key(self):
        app = LayoutEditorApp(keymap="vim")
        async with app.run_test() as pilot:
            await pilot.press("s")                  # vim: split horizontal
            self.assertEqual(app.model.notation(), "H[a, b]")

    async def test_vim_h_navigates_to_parent(self):
        app = LayoutEditorApp(keymap="vim")
        async with app.run_test() as pilot:
            await pilot.press("s")                  # H[a, b], selected b (leaf)
            await pilot.press("h")                  # nav to parent (the H group)
            self.assertIsInstance(app.model.selected, Group)
            self.assertEqual(app.model.selected.kind, "H")

    async def test_vim_bar_shows_mode_and_nav_keys(self):
        app = LayoutEditorApp(keymap="vim")
        async with app.run_test():
            text = app._shortcuts_text
            self.assertIn("-- NORMAL --", text)     # modal indicator
            self.assertIn("h parent", text)         # hjkl navigation
            self.assertIn("j down", text)

    async def test_backslash_toggles_keymap_and_bar(self):
        app = LayoutEditorApp()                     # starts standard
        async with app.run_test() as pilot:
            self.assertEqual(app.keymap, "standard")
            await pilot.press("backslash")
            self.assertEqual(app.keymap, "vim")
            self.assertIn("-- NORMAL --", app._shortcuts_text)
            await pilot.press("backslash")
            self.assertEqual(app.keymap, "standard")

    async def test_standard_keymap_still_splits_with_h(self):
        app = LayoutEditorApp(keymap="standard")
        async with app.run_test() as pilot:
            await pilot.press("h")                  # standard: split H (regression)
            self.assertEqual(app.model.notation(), "H[a, b]")

    async def test_vim_hjkl_navigate_tree(self):
        from hy3_layout import Group, Window
        from hy3_layout_tui_model import TuiModel
        layout = TuiModel(Group("V", [Window("a"),
                                      Group("H", [Window("b"), Window("c")])]))
        app = LayoutEditorApp(layout_model=layout, keymap="vim")
        async with app.run_test() as pilot:
            root = app.model.root                   # V, selected at start
            self.assertIs(app.model.selected, root)
            await pilot.press("l")                  # l -> first child (a)
            await pilot.pause()
            self.assertEqual(app.model.selected.label, "a")
            await pilot.press("h")                  # h -> parent (V)
            await pilot.pause()
            self.assertIs(app.model.selected, root)
            await pilot.press("j")                  # j -> down to a
            await pilot.pause()
            self.assertEqual(app.model.selected.label, "a")
            await pilot.press("j")                  # j -> down to the H group
            await pilot.pause()
            self.assertEqual(app.model.selected.kind, "H")
            await pilot.press("k")                  # k -> up to a
            await pilot.pause()
            self.assertEqual(app.model.selected.label, "a")

    async def test_repeated_jk_navigation_is_stable(self):
        # Regression: rapid up/down used to feed a preview-relayout loop that
        # backed up the message queue and froze the UI after enough presses.
        from hy3_layout import Group, Window
        from hy3_layout_tui_model import TuiModel
        layout = TuiModel(Group("V", [Window("a"), Window("b"), Window("c")]))
        app = LayoutEditorApp(layout_model=layout, keymap="vim")
        async with app.run_test() as pilot:
            for _ in range(25):
                await pilot.press("j")
            for _ in range(25):
                await pilot.press("k")
            await pilot.pause()
            # still responsive: navigation still moves the selection (not frozen)
            before = app.model.selected
            await pilot.press("j")
            await pilot.pause()
            self.assertIsNot(app.model.selected, before)


class ActionsTest(unittest.IsolatedAsyncioTestCase):
    async def test_build_reports_verify_ok(self):
        calls = {}
        orig_build = engine.run_build
        orig_dump = engine.dump_workspace_tree
        orig_ast = engine.ast_from_tree
        engine.run_build = lambda node, ws=None: calls.setdefault("ws", ws)
        engine.dump_workspace_tree = lambda ws: {"workspace": ws}
        engine.ast_from_tree = lambda tree: Group("H", [Window("a"), Window("b")])
        try:
            app = LayoutEditorApp()
            async with app.run_test() as pilot:
                await pilot.press("h")               # H[a, b]
                status = app.build_on(8)
                self.assertEqual(status, "verify: ok")
                self.assertEqual(calls["ws"], 8)
        finally:
            engine.run_build = orig_build
            engine.dump_workspace_tree = orig_dump
            engine.ast_from_tree = orig_ast

    async def test_build_reports_divergence(self):
        orig_build = engine.run_build
        orig_dump = engine.dump_workspace_tree
        orig_ast = engine.ast_from_tree
        engine.run_build = lambda node, ws=None: None
        engine.dump_workspace_tree = lambda ws: {"workspace": ws}
        engine.ast_from_tree = lambda tree: Window("a")    # built a single leaf
        try:
            app = LayoutEditorApp()
            async with app.run_test() as pilot:
                await pilot.press("h")               # drew H[a, b]
                status = app.build_on(8)
                self.assertTrue(status.startswith("built != drawn"))
        finally:
            engine.run_build = orig_build
            engine.dump_workspace_tree = orig_dump
            engine.ast_from_tree = orig_ast

    async def test_export_shows_notation(self):
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.press("h")
            self.assertEqual(app.export(), "H[a, b]")

    async def test_grab_live_workspace_seeds_model(self):
        orig_dump = engine.dump_workspace_tree
        orig_info = engine.active_addr_info
        orig_ast = engine.ast_from_tree
        engine.dump_workspace_tree = lambda ws: {"workspace": ws}
        engine.active_addr_info = lambda: {}
        engine.ast_from_tree = lambda tree, info=None: Group(
            "V", [Window("a", "firefox"), Window("b")])
        try:
            app = LayoutEditorApp()
            async with app.run_test():
                status = app.grab_from_ws(3)
                self.assertEqual(status, "grabbed ws3")
                self.assertEqual(app.model.notation(), "V[a=firefox, b]")
        finally:
            engine.dump_workspace_tree = orig_dump
            engine.active_addr_info = orig_info
            engine.ast_from_tree = orig_ast

    async def test_grab_empty_workspace_reports(self):
        orig_dump = engine.dump_workspace_tree
        orig_info = engine.active_addr_info
        orig_ast = engine.ast_from_tree
        engine.dump_workspace_tree = lambda ws: {"workspace": ws}
        engine.active_addr_info = lambda: {}
        engine.ast_from_tree = lambda tree, info=None: None
        try:
            app = LayoutEditorApp()
            async with app.run_test():
                self.assertEqual(app.grab_from_ws(9), "ws9 is empty")
        finally:
            engine.dump_workspace_tree = orig_dump
            engine.active_addr_info = orig_info
            engine.ast_from_tree = orig_ast


class CommandLineTest(unittest.IsolatedAsyncioTestCase):
    async def test_colon_opens_command_line(self):
        from hy3_layout_tui import CommandLine
        app = LayoutEditorApp()
        async with app.run_test() as pilot:
            await pilot.press("colon")
            await pilot.pause()
            self.assertIsInstance(app.screen, CommandLine)

    async def test_command_g_grabs_active_workspace(self):
        captured = {}
        orig_active = engine._active_ws_id
        orig_dump = engine.dump_workspace_tree
        orig_info = engine.active_addr_info
        orig_ast = engine.ast_from_tree

        def fake_dump(ws):
            captured["ws"] = ws
            return {"ws": ws}

        engine._active_ws_id = lambda: 4
        engine.dump_workspace_tree = fake_dump
        engine.active_addr_info = lambda: {}
        engine.ast_from_tree = lambda tree, info=None: Window("a", "kitty")
        try:
            app = LayoutEditorApp()
            async with app.run_test():
                app._run_command("g")              # no number -> active ws (4)
                self.assertEqual(captured["ws"], 4)
                self.assertEqual(app.model.notation(), "a=kitty")
        finally:
            engine._active_ws_id = orig_active
            engine.dump_workspace_tree = orig_dump
            engine.active_addr_info = orig_info
            engine.ast_from_tree = orig_ast

    async def test_command_g_with_number_grabs_that_workspace(self):
        captured = {}
        orig_dump = engine.dump_workspace_tree
        orig_info = engine.active_addr_info
        orig_ast = engine.ast_from_tree

        def fake_dump(ws):
            captured["ws"] = ws
            return {"ws": ws}

        engine.dump_workspace_tree = fake_dump
        engine.active_addr_info = lambda: {}
        engine.ast_from_tree = lambda tree, info=None: Window("a", "kitty")
        try:
            app = LayoutEditorApp()
            async with app.run_test():
                app._run_command("g 7")            # explicit workspace 7
                self.assertEqual(captured["ws"], 7)
        finally:
            engine.dump_workspace_tree = orig_dump
            engine.active_addr_info = orig_info
            engine.ast_from_tree = orig_ast

    async def test_command_b_builds_on_workspace(self):
        captured = {}
        orig_build = engine.run_build
        orig_dump = engine.dump_workspace_tree
        orig_ast = engine.ast_from_tree

        def fake_build(node, ws=None):
            captured["ws"] = ws

        engine.run_build = fake_build
        engine.dump_workspace_tree = lambda ws: {"ws": ws}
        engine.ast_from_tree = lambda tree: Group("H", [Window("a"), Window("b")])
        try:
            app = LayoutEditorApp()
            async with app.run_test() as pilot:
                await pilot.press("h")             # H[a, b]
                app._run_command("b 5")            # :b 5 -> build on ws 5
                self.assertEqual(captured["ws"], 5)
        finally:
            engine.run_build = orig_build
            engine.dump_workspace_tree = orig_dump
            engine.ast_from_tree = orig_ast

    async def test_command_w_saves_workspace(self):
        import hy3_layout_tui_model as tmodel
        captured = {}
        orig = tmodel.save_notation

        def fake_save(path, ws, notation):
            captured["ws"] = ws

        tmodel.save_notation = fake_save
        try:
            app = LayoutEditorApp()
            async with app.run_test():
                app._run_command("w 2")            # :w 2 -> save as ws 2
                self.assertEqual(captured["ws"], 2)
        finally:
            tmodel.save_notation = orig

    async def test_command_e_loads_workspace(self):
        import hy3_layout_tui_model as tmodel
        captured = {}
        orig = tmodel.load_model

        def fake_load(path, ws):
            captured["ws"] = ws
            return tmodel.TuiModel()

        tmodel.load_model = fake_load
        try:
            app = LayoutEditorApp()
            async with app.run_test():
                app._run_command("e 3")            # :e 3 -> load ws 3
                self.assertEqual(captured["ws"], 3)
        finally:
            tmodel.load_model = orig


class LayoutRenderTest(unittest.TestCase):
    def test_h_renders_side_by_side(self):
        art = render_layout_ascii(Group("H", [Window("a"), Window("b")]), 20, 4)
        row = next(line for line in art.splitlines() if "a" in line and "b" in line)
        self.assertLess(row.index("a"), row.index("b"))

    def test_v_renders_stacked(self):
        art = render_layout_ascii(Group("V", [Window("a"), Window("b")]), 20, 8)
        lines = art.splitlines()
        a_row = next(i for i, line in enumerate(lines) if "a" in line)
        b_row = next(i for i, line in enumerate(lines) if "b" in line)
        self.assertLess(a_row, b_row)

    def test_t_shows_tab_strip(self):
        art = render_layout_ascii(Group("T", [Window("a"), Window("b")]), 20, 6)
        self.assertIn("[a]", art)
        self.assertIn("[b]", art)

    def test_selected_node_marked(self):
        leaf = Window("x")
        art = render_layout_ascii(leaf, 12, 4, selected=leaf)
        self.assertIn("*", art)             # selected box uses '*' corners

    def test_lines_are_uniform_full_width(self):
        # every line is exactly `width` chars and there are exactly `height`
        # lines -- so each frame overwrites the previous one with no stale
        # trailing glyphs (the up/down preview-artifact regression).
        art = render_layout_ascii(
            Group("V", [Window("a", "firefox"), Window("b")]), 20, 8)
        lines = art.split("\n")
        self.assertEqual(len(lines), 8)
        self.assertTrue(all(len(line) == 20 for line in lines))


class LoggingTest(unittest.TestCase):
    def test_setup_logging_writes_to_file(self):
        import os
        import tempfile
        from hy3_layout_tui import _setup_logging, _log
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "sub", "tui.log")     # also exercises makedirs
            _setup_logging(path)
            try:
                _log.debug("probe-%d", 7)
                for handler in _log.handlers:
                    handler.flush()
                with open(path) as fh:
                    self.assertIn("probe-7", fh.read())
            finally:
                for handler in list(_log.handlers):
                    handler.close()
                    _log.removeHandler(handler)
                _log.setLevel(logging.NOTSET)


if __name__ == "__main__":
    unittest.main()
