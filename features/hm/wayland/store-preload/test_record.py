"""Tests for /proc scanning and app attribution."""

from __future__ import annotations

import os
import tempfile
import unittest

import record

STORE = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-x-1.0"


class TestAppFor(unittest.TestCase):
    def test_exact_match(self) -> None:
        self.assertEqual(record.app_for("rofi", ["rofi", "kitty"]), "rofi")

    def test_hyphenated_variant_matches(self) -> None:
        self.assertEqual(record.app_for("firefox-bin", ["firefox"]), "firefox")

    def test_profile_does_not_match_rofi(self) -> None:
        """The bug this function exists to prevent."""
        self.assertIsNone(record.app_for("profile", ["rofi"]))

    def test_longer_name_does_not_match(self) -> None:
        self.assertIsNone(record.app_for("rofimoji", ["rofi"]))

    def test_unknown_returns_none(self) -> None:
        self.assertIsNone(record.app_for("bash", ["rofi"]))


class TestMappedStoreFiles(unittest.TestCase):
    def _maps(self, body: str) -> str:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "maps")
        with open(p, "w", encoding="utf-8") as f:
            f.write(body)
        return p

    def test_extracts_store_paths(self) -> None:
        p = self._maps(
            f"7f00-7f01 r-xp 00000000 00:1b 12345 {STORE}/lib/libx.so\n"
            "7f02-7f03 rw-p 00000000 00:00 0 [heap]\n"
        )
        self.assertEqual(record.mapped_store_files(p), {f"{STORE}/lib/libx.so"})

    def test_skips_deleted_mappings(self) -> None:
        p = self._maps(f"7f00-7f01 r-xp 0 00:1b 1 {STORE}/lib/gone.so (deleted)\n")
        self.assertEqual(record.mapped_store_files(p), set())

    def test_unreadable_maps_is_empty(self) -> None:
        self.assertEqual(record.mapped_store_files("/nonexistent/maps"), set())


class TestScan(unittest.TestCase):
    def test_attributes_mappings_to_the_right_app(self) -> None:
        procfs = tempfile.mkdtemp()
        # A tracked process.
        pid = os.path.join(procfs, "1000")
        os.makedirs(pid)
        target = os.path.join(procfs, ".rofi-wrapped")
        open(target, "w", encoding="utf-8").close()
        os.symlink(target, os.path.join(pid, "exe"))
        with open(os.path.join(pid, "maps"), "w", encoding="utf-8") as f:
            f.write(f"7f00-7f01 r-xp 0 00:1b 1 {STORE}/lib/librofi.so\n")
        # A decoy whose name contains 'rofi' as a substring.
        pid2 = os.path.join(procfs, "1001")
        os.makedirs(pid2)
        target2 = os.path.join(procfs, "profile")
        open(target2, "w", encoding="utf-8").close()
        os.symlink(target2, os.path.join(pid2, "exe"))
        with open(os.path.join(pid2, "maps"), "w", encoding="utf-8") as f:
            f.write(f"7f00-7f01 r-xp 0 00:1b 1 {STORE}/lib/decoy.so\n")

        got = record.scan(["rofi"], procfs=procfs)
        self.assertEqual(got, {"rofi": [f"{STORE}/lib/librofi.so"]})

    def test_no_matching_processes_is_empty(self) -> None:
        procfs = tempfile.mkdtemp()
        self.assertEqual(record.scan(["rofi"], procfs=procfs), {})


if __name__ == "__main__":
    unittest.main()
