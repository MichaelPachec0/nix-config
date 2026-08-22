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

    def test_save_then_load_roundtrips(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "sub", "manifest.json")
        manifest.save(p, {"rofi": ["/nix/store/b", "/nix/store/a"]})
        self.assertEqual(manifest.load(p), {"rofi": ["/nix/store/a", "/nix/store/b"]})

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
