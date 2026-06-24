import os
import tempfile
import unittest

import hy3_layout_apps as apps


class FieldCodeTest(unittest.TestCase):
    def test_strip_drops_codes_and_keeps_literal_percent(self):
        self.assertEqual(apps.strip_field_codes("foo %U --bar"), "foo --bar")
        self.assertEqual(apps.strip_field_codes("foo %%"), "foo %")
        self.assertEqual(apps.strip_field_codes("kitty"), "kitty")


class DesktopParseTest(unittest.TestCase):
    def test_parse_basic(self):
        app = apps.parse_desktop_text(
            "[Desktop Entry]\nType=Application\nName=Kitty\nExec=kitty %F\n")
        self.assertEqual(app.name, "Kitty")
        self.assertEqual(app.exec_cmd, "kitty")
        self.assertFalse(app.terminal)

    def test_parse_terminal_flag(self):
        app = apps.parse_desktop_text(
            "[Desktop Entry]\nType=Application\nName=Top\nExec=htop\nTerminal=true\n")
        self.assertTrue(app.terminal)

    def test_skip_nodisplay(self):
        self.assertIsNone(apps.parse_desktop_text(
            "[Desktop Entry]\nType=Application\nName=X\nExec=x\nNoDisplay=true\n"))

    def test_skip_hidden(self):
        self.assertIsNone(apps.parse_desktop_text(
            "[Desktop Entry]\nType=Application\nName=X\nExec=x\nHidden=true\n"))

    def test_skip_non_application(self):
        self.assertIsNone(apps.parse_desktop_text(
            "[Desktop Entry]\nType=Link\nName=X\nURL=http://x\n"))

    def test_malformed_returns_none(self):
        self.assertIsNone(apps.parse_desktop_text("not an ini file at all"))


class DiscoverTest(unittest.TestCase):
    def test_discover_reads_dir_and_sorts(self):
        with tempfile.TemporaryDirectory() as d:
            appdir = os.path.join(d, "applications")
            os.makedirs(appdir)
            with open(os.path.join(appdir, "z.desktop"), "w") as fh:
                fh.write("[Desktop Entry]\nType=Application\nName=Zed\nExec=zed\n")
            with open(os.path.join(appdir, "a.desktop"), "w") as fh:
                fh.write("[Desktop Entry]\nType=Application\nName=Atom\nExec=atom\n")
            env = {"XDG_DATA_HOME": d, "XDG_DATA_DIRS": ""}
            names = [a.name for a in apps.discover_apps(env)]
            self.assertEqual(names, ["Atom", "Zed"])


class CommandBuilderTest(unittest.TestCase):
    def test_plain_command(self):
        spec = apps.CommandSpec(base="kitty")
        self.assertEqual(apps.build_command(spec), "kitty")

    def test_command_with_args(self):
        spec = apps.CommandSpec(base="nvim", args="flake.nix")
        self.assertEqual(apps.build_command(spec), "nvim flake.nix")

    def test_terminal_wrapping(self):
        spec = apps.CommandSpec(base="nvim", in_terminal=True, terminal="kitty")
        self.assertEqual(apps.build_command(spec), "kitty -e nvim")

    def test_terminal_wrapping_with_args(self):
        spec = apps.CommandSpec(base="nvim", args="flake.nix",
                                in_terminal=True, terminal="alacritty")
        self.assertEqual(apps.build_command(spec), "alacritty -e nvim flake.nix")

    def test_default_terminal(self):
        self.assertEqual(apps.default_terminal({"TERMINAL": "foot"}), "foot")
        self.assertEqual(apps.default_terminal({}), "kitty")


if __name__ == "__main__":
    unittest.main()
