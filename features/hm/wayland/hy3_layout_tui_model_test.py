import os
import tempfile
import unittest

import hy3_layout_tui_model as m
from hy3_layout import Group, Window


class LabelTest(unittest.TestCase):
    def test_label_sequence(self):
        self.assertEqual([m.label_at(i) for i in range(3)], ["a", "b", "c"])
        self.assertEqual(m.label_at(25), "z")
        self.assertEqual(m.label_at(26), "aa")


class SimpleOpsTest(unittest.TestCase):
    def test_new_model_is_single_leaf(self):
        model = m.TuiModel()
        self.assertEqual(model.notation(), "a")
        self.assertIs(model.selected, model.root)

    def test_split_leaf_becomes_group(self):
        model = m.TuiModel()
        new = model.split("H")
        self.assertEqual(model.notation(), "H[a, b]")
        self.assertIs(model.selected, new)
        self.assertEqual(new.label, "b")

    def test_split_nested_uses_fresh_label(self):
        model = m.TuiModel()
        model.split("H")          # H[a, b], selected b
        model.split("V")          # H[a, V[b, c]], selected c
        self.assertEqual(model.notation(), "H[a, V[b, c]]")

    def test_split_requires_leaf(self):
        model = m.TuiModel()
        model.split("H")
        model.selected = model.root   # a Group
        with self.assertRaises(ValueError):
            model.split("H")

    def test_set_orient_changes_group_kind(self):
        model = m.TuiModel()
        model.split("H")
        model.selected = model.root
        model.set_orient("T")
        self.assertEqual(model.notation(), "T[a, b]")

    def test_assign_sets_command_and_cwd(self):
        model = m.TuiModel()
        model.assign("kitty -e nvim flake.nix", "/tmp")
        self.assertEqual(model.notation(), 'a="kitty -e nvim flake.nix"@/tmp')

    def test_assign_roundtrips_through_parser(self):
        from hy3_layout import parse, to_notation
        model = m.TuiModel()
        model.assign("kitty -e nvim flake.nix", "/tmp")
        self.assertEqual(parse(to_notation(model.root)), model.root)

    def test_move_reorders_siblings(self):
        model = m.TuiModel()
        model.split("H")          # H[a, b], selected b
        model.move(-1)            # b before a
        self.assertEqual(model.notation(), "H[b, a]")

    def test_move_root_is_noop(self):
        model = m.TuiModel()
        model.move(-1)
        self.assertEqual(model.notation(), "a")


class DeleteTest(unittest.TestCase):
    def test_delete_collapses_pair_to_sibling(self):
        model = m.TuiModel()
        model.split("H")          # H[a, b], selected b
        model.delete()            # remove b -> single child a -> collapse
        self.assertEqual(model.notation(), "a")
        self.assertIsInstance(model.selected, Window)

    def test_delete_keeps_group_with_remaining_children(self):
        model = m.TuiModel()
        model.split("H")          # H[a, b], selected b
        model.split("V")          # H[a, V[b, c]], selected c
        model.selected = model.root.children[0]   # a
        model.delete()            # H[V[b, c]] -> collapse -> V[b, c]
        self.assertEqual(model.notation(), "V[b, c]")

    def test_delete_root_resets_to_empty_leaf(self):
        model = m.TuiModel()
        model.assign("kitty")
        model.delete()
        self.assertEqual(model.notation(), "a")
        self.assertIs(model.selected, model.root)

    def test_delete_three_child_group_selects_neighbour(self):
        model = m.TuiModel(Group("H", [Window("a"), Window("b"), Window("c")]))
        model.selected = model.root.children[1]   # b
        model.delete()            # H[a, c], select index 1 -> c
        self.assertEqual(model.notation(), "H[a, c]")
        self.assertEqual(model.selected.label, "c")


class SaveLoadTest(unittest.TestCase):
    def test_parse_save_text_rejects_bad_json(self):
        with self.assertRaises(m.SaveFileError):
            m.parse_save_text("{ not json")

    def test_validate_rejects_missing_version(self):
        with self.assertRaises(m.SaveFileError):
            m.validate_save_data({"workspaces": {}})

    def test_validate_rejects_non_string_entry(self):
        with self.assertRaises(m.SaveFileError):
            m.validate_save_data({"version": 1, "workspaces": {"1": 5}})

    def test_model_from_save_data_loads_entry(self):
        data = {"version": 1, "workspaces": {"2": "H[a, b]"}}
        model = m.model_from_save_data(data, 2)
        self.assertEqual(model.notation(), "H[a, b]")

    def test_model_from_save_data_missing_ws(self):
        data = {"version": 1, "workspaces": {"2": "H[a, b]"}}
        with self.assertRaises(m.SaveFileError):
            m.model_from_save_data(data, 9)

    def test_model_from_save_data_invalid_notation(self):
        data = {"version": 1, "workspaces": {"2": "H[a,"}}
        with self.assertRaises(m.SaveFileError):
            m.model_from_save_data(data, 2)

    def test_load_model_missing_file_raises_savefileerror(self):
        with self.assertRaises(m.SaveFileError):
            m.load_model("/nonexistent/dir/does/not/exist.json", 1)

    def test_load_model_directory_path_raises_savefileerror(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(m.SaveFileError):
                m.load_model(d, 1)   # a directory -> OSError, not FileNotFoundError

    def test_model_from_save_data_missing_workspaces_raises_savefileerror(self):
        with self.assertRaises(m.SaveFileError):
            m.model_from_save_data({"version": 1}, 1)


class SaveWriteTest(unittest.TestCase):
    def test_save_creates_and_merges(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "sub", "layouts.json")
            m.save_notation(path, 1, "H[a, b]")
            m.save_notation(path, 2, "V[c, d]")
            with open(path) as fh:
                data = m.parse_save_text(fh.read())
            self.assertEqual(data["workspaces"], {"1": "H[a, b]", "2": "V[c, d]"})

    def test_save_refuses_to_clobber_corrupt(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "layouts.json")
            with open(path, "w") as fh:
                fh.write("{ corrupt")
            with self.assertRaises(m.SaveFileError):
                m.save_notation(path, 1, "H[a, b]")

    def test_save_to_unwritable_path_raises_savefileerror(self):
        with tempfile.TemporaryDirectory() as d:
            blocker = os.path.join(d, "afile")
            with open(blocker, "w") as fh:
                fh.write("x")
            # a regular file as a path component -> makedirs/open raise OSError
            path = os.path.join(blocker, "layouts.json")
            with self.assertRaises(m.SaveFileError):
                m.save_notation(path, 1, "H[a, b]")


if __name__ == "__main__":
    unittest.main()
