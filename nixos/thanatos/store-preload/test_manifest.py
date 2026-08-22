"""Tests for the persisted manifest."""

from __future__ import annotations

import json
import os
import tempfile
import unittest

import manifest


class TestManifest(unittest.TestCase):
    def test_load_missing_file_is_empty(self) -> None:
        self.assertEqual(manifest.load("/nonexistent/manifest.json"), {})

    def test_load_corrupt_file_is_empty(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write("{not json")
            p = f.name
        self.addCleanup(os.unlink, p)
        self.assertEqual(manifest.load(p), {})

    def test_load_wrong_version_is_empty(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"version": 99, "apps": {"rofi": ["/nix/store/x"]}}, f)
            p = f.name
        self.addCleanup(os.unlink, p)
        self.assertEqual(manifest.load(p), {})

    def test_load_version_1_is_discarded_not_crashed(self) -> None:
        """v1 held name -> [files]; v2 holds name -> {root, files}."""
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"version": 1, "apps": {"rofi": ["/nix/store/x"]}}, f)
            p = f.name
        self.addCleanup(os.unlink, p)
        self.assertEqual(manifest.load(p), {})
        self.assertEqual(manifest.load_roots(p), {})

    def test_load_ignores_malformed_app_entry(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(
                {
                    "version": manifest.MANIFEST_VERSION,
                    "apps": {"rofi": ["/nix/store/x"], "kitty": {"files": ["/a"]}},
                },
                f,
            )
            p = f.name
        self.addCleanup(os.unlink, p)
        self.assertEqual(manifest.load(p), {"kitty": ["/a"]})

    def test_save_then_load_roundtrips(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "sub", "manifest.json")
        manifest.save(p, {"rofi": ["/nix/store/b", "/nix/store/a"]}, {})
        self.assertEqual(
            manifest.load(p), {"rofi": ["/nix/store/a", "/nix/store/b"]}
        )

    def test_roots_roundtrip(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "manifest.json")
        manifest.save(p, {"rofi": ["/a"]}, {"rofi": "/nix/store/h-rofi-1.0"})
        self.assertEqual(manifest.load_roots(p), {"rofi": "/nix/store/h-rofi-1.0"})

    def test_missing_root_is_absent_not_empty_string(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "manifest.json")
        manifest.save(p, {"rofi": ["/a"]}, {})
        self.assertEqual(manifest.load_roots(p), {})

    def test_replace_drops_the_old_list(self) -> None:
        base: manifest.Manifest = {"rofi": ["/old1", "/old2"], "kitty": ["/k"]}
        out = manifest.replace(base, "rofi", ["/new"])
        self.assertEqual(out, {"rofi": ["/new"], "kitty": ["/k"]})
        self.assertEqual(base["rofi"], ["/old1", "/old2"])

    def test_restrict_drops_unlisted_apps(self) -> None:
        base: manifest.Manifest = {"firefox": ["/a"], "rofi": ["/b"]}
        self.assertEqual(manifest.restrict(base, ["rofi"]), {"rofi": ["/b"]})

    def test_merge_unions_and_dedupes(self) -> None:
        base: manifest.Manifest = {"rofi": ["/a"]}
        out = manifest.merge(base, "rofi", ["/b", "/a"])
        self.assertEqual(out["rofi"], ["/a", "/b"])

    def test_merge_does_not_mutate_input(self) -> None:
        base: manifest.Manifest = {"rofi": ["/a"]}
        manifest.merge(base, "rofi", ["/b"])
        self.assertEqual(base, {"rofi": ["/a"]})

    def test_merge_creates_new_app(self) -> None:
        out = manifest.merge({}, "kitty", ["/a"])
        self.assertEqual(out, {"kitty": ["/a"]})

    def test_prune_drops_missing_paths(self) -> None:
        m: manifest.Manifest = {"rofi": ["/gone", "/here"]}
        out = manifest.prune(m, exists=lambda p: p == "/here")
        self.assertEqual(out, {"rofi": ["/here"]})


if __name__ == "__main__":
    unittest.main()
