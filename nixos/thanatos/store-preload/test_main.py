"""Tests for the command layer: invalidation, pruning and reporting."""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import tempfile
import unittest
from typing import Sequence
from unittest import mock

import main
import manifest
import record
import resolve

ROOT_A = "/nix/store/fsakzlw63avfvkanzzvrzmylzs60qxwa-rofi-2.0"
ROOT_B = "/nix/store/7mbvdxzcg00bqnyz13r6yg2n6lncpl52-rofi-2.1"


def _args(**kw: object) -> argparse.Namespace:
    base: dict[str, object] = {
        "apps": ["rofi"],
        "workers": 2,
        "max_bytes": 1 << 30,
    }
    base.update(kw)
    return argparse.Namespace(**base)


def _run_record(args: argparse.Namespace) -> str:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = main.cmd_record(args)
    assert rc == 0
    return buf.getvalue()


class TestRecordInvalidation(unittest.TestCase):
    """C1: retained generations keep old paths alive, so prune cannot see a
    rebuild. The app's store root is the stamp that can."""

    def setUp(self) -> None:
        self.state = os.path.join(tempfile.mkdtemp(), "manifest.json")

    def _record(self, files: Sequence[str], binary: str) -> str:
        with mock.patch.object(
            record, "scan", return_value={"rofi": list(files)}
        ), mock.patch.object(
            resolve, "real_binary", return_value=binary + "/bin/rofi"
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            return _run_record(_args(state=self.state))

    def test_same_root_merges(self) -> None:
        self._record([ROOT_A + "/a"], ROOT_A)
        self._record([ROOT_A + "/b"], ROOT_A)
        self.assertEqual(
            manifest.load(self.state), {"rofi": [ROOT_A + "/a", ROOT_A + "/b"]}
        )

    def test_changed_root_replaces_when_the_scan_corroborates(self) -> None:
        self._record([ROOT_A + "/a"], ROOT_A)
        out = self._record([ROOT_B + "/b"], ROOT_B)
        self.assertEqual(manifest.load(self.state), {"rofi": [ROOT_B + "/b"]})
        self.assertEqual(manifest.load_roots(self.state), {"rofi": ROOT_B})
        self.assertIn("reset rofi", out)

    def test_changed_root_without_corroboration_merges(self) -> None:
        """Rebuild while the app runs: PATH says new, /proc still says old.

        Replacing here would stamp the old generation's paths as the new one,
        and the stamp would never fire again.
        """
        self._record([ROOT_A + "/a"], ROOT_A)
        out = self._record([ROOT_A + "/b"], ROOT_B)
        self.assertEqual(
            manifest.load(self.state), {"rofi": [ROOT_A + "/a", ROOT_A + "/b"]}
        )
        # The stale root is kept on purpose so the check fires again later.
        self.assertEqual(manifest.load_roots(self.state), {"rofi": ROOT_A})
        self.assertNotIn("reset", out)

    def test_reset_fires_on_the_tick_after_the_app_restarts(self) -> None:
        self._record([ROOT_A + "/a"], ROOT_A)
        self._record([ROOT_A + "/b"], ROOT_B)
        out = self._record([ROOT_B + "/c"], ROOT_B)
        self.assertEqual(manifest.load(self.state), {"rofi": [ROOT_B + "/c"]})
        self.assertEqual(manifest.load_roots(self.state), {"rofi": ROOT_B})
        self.assertIn("reset rofi", out)

    def test_root_is_stored_on_first_record(self) -> None:
        self._record([ROOT_A + "/a"], ROOT_A)
        self.assertEqual(manifest.load_roots(self.state), {"rofi": ROOT_A})

    def test_first_record_is_not_reported_as_a_reset(self) -> None:
        out = self._record([ROOT_A + "/a"], ROOT_A)
        self.assertNotIn("reset", out)

    def test_unresolvable_binary_still_merges(self) -> None:
        with mock.patch.object(
            record, "scan", return_value={"rofi": ["/a"]}
        ), mock.patch.object(
            resolve, "real_binary", return_value=None
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            _run_record(_args(state=self.state))
        self.assertEqual(manifest.load(self.state), {"rofi": ["/a"]})
        self.assertEqual(manifest.load_roots(self.state), {})


class TestRecordDropsRenamedApps(unittest.TestCase):
    """I3: firefox -> firefox-devedition orphaned ~350 paths forever."""

    def test_key_not_in_apps_is_dropped(self) -> None:
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"firefox": ["/old"], "rofi": ["/a"]}, {})
        with mock.patch.object(
            record, "scan", return_value={}
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            _run_record(_args(state=state, apps=["rofi", "firefox-devedition"]))
        self.assertEqual(manifest.load(state), {"rofi": ["/a"]})

    def test_stale_root_is_dropped_with_its_app(self) -> None:
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"firefox": ["/old"]}, {"firefox": ROOT_A})
        with mock.patch.object(
            record, "scan", return_value={}
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            _run_record(_args(state=state, apps=["rofi"]))
        self.assertEqual(manifest.load_roots(state), {})


class TestRecordSkipsUnchangedWrites(unittest.TestCase):
    """I4: the timer fires every 30s; do not fsync for nothing."""

    def test_second_identical_record_does_not_save(self) -> None:
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        with mock.patch.object(
            record, "scan", return_value={"rofi": ["/a"]}
        ), mock.patch.object(
            resolve, "real_binary", return_value=ROOT_A + "/bin/rofi"
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            _run_record(_args(state=state))
            with mock.patch.object(manifest, "save") as saver:
                out = _run_record(_args(state=state))
        saver.assert_not_called()
        self.assertIn("unchanged", out)

    def test_a_new_path_still_saves(self) -> None:
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        with mock.patch.object(
            resolve, "real_binary", return_value=ROOT_A + "/bin/rofi"
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            with mock.patch.object(
                record, "scan", return_value={"rofi": ["/a"]}
            ):
                _run_record(_args(state=state))
            with mock.patch.object(
                record, "scan", return_value={"rofi": ["/b"]}
            ):
                out = _run_record(_args(state=state))
        self.assertEqual(manifest.load(state), {"rofi": ["/a", "/b"]})
        self.assertNotIn("unchanged", out)

    def test_pruned_path_is_a_change_and_saves(self) -> None:
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": ["/gone", "/here"]}, {})
        with mock.patch.object(record, "scan", return_value={}):
            out = _run_record(_args(state=state))
        self.assertEqual(manifest.load(state), {"rofi": []})
        self.assertNotIn("unchanged", out)


class TestWarmReporting(unittest.TestCase):
    """I2: the headline must be able to fail."""

    def _file(self, size: int) -> str:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "f.bin")
        with open(p, "wb") as f:
            f.write(os.urandom(4096) * (size // 4096))
        return p

    def test_denominator_is_the_union_not_the_planned_subset(self) -> None:
        a, b = self._file(2 << 20), self._file(2 << 20)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a, b]}, {})
        # The cap admits one file; the union is still both.
        args = _args(state=state, max_bytes=2 << 20, apps=["rofi"])
        buf = io.StringIO()
        with mock.patch.object(resolve, "seed", return_value=[]):
            with contextlib.redirect_stdout(buf):
                self.assertEqual(main.cmd_warm(args), 0)
        out = buf.getvalue()
        self.assertIn("1 files, 2.0 MB in", out)
        self.assertIn("of 4.0 MB", out)

    def test_status_and_warm_share_the_denominator(self) -> None:
        a, b = self._file(8192), self._file(8192)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a, b]}, {})
        with mock.patch.object(resolve, "seed", return_value=[]):
            warm_buf, status_buf = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(warm_buf):
                main.cmd_warm(_args(state=state))
            with contextlib.redirect_stdout(status_buf):
                main.cmd_status(_args(state=state))
        # Both report the same total size for the same file set.
        self.assertIn(main._mb(16384), warm_buf.getvalue())
        self.assertIn(main._mb(16384), status_buf.getvalue())

    def test_negative_delta_carries_one_sign(self) -> None:
        """Pages can be evicted mid-pass; "+-0.3 MB" is not a number."""
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": ["/nonexistent"]}, {})
        buf = io.StringIO()
        with mock.patch.object(resolve, "seed", return_value=[]), mock.patch.object(
            main, "_residency", side_effect=[(1 << 20, 4 << 20), (0, 4 << 20)]
        ):
            with contextlib.redirect_stdout(buf):
                main.cmd_warm(_args(state=state))
        out = buf.getvalue()
        self.assertIn("(-1.0 MB,", out)
        self.assertNotIn("+-", out)

    def test_delta_formats_both_signs(self) -> None:
        self.assertEqual(main._delta(2 << 20), "+2.0 MB")
        self.assertEqual(main._delta(-(2 << 20)), "-2.0 MB")
        self.assertEqual(main._delta(0), "+0.0 MB")

    def test_residency_totals_the_whole_list(self) -> None:
        a, b = self._file(8192), self._file(8192)
        res, total = main._residency([a, b, "/nonexistent"])
        self.assertEqual(total, 16384)
        self.assertLessEqual(res, total)


if __name__ == "__main__":
    unittest.main()
