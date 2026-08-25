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
import warm

ROOT_A = "/nix/store/fsakzlw63avfvkanzzvrzmylzs60qxwa-rofi-2.0"
ROOT_B = "/nix/store/7mbvdxzcg00bqnyz13r6yg2n6lncpl52-rofi-2.1"

# Shared, deliberately empty: load_seed treats a missing app file as [], not
# an error, so this is the default "nothing seeded" seed_dir for tests that
# do not care about the build-time seed.
EMPTY_SEED_DIR = tempfile.mkdtemp()


def _seed_dir_with(app: str, first_line: str) -> str:
    """A seed dir containing one file for app, whose first line is first_line.

    The first line is what seed_stamp reads as the generation stamp.
    """
    d = tempfile.mkdtemp()
    with open(os.path.join(d, app), "w", encoding="utf-8") as f:
        f.write(first_line + "\n")
    return d


def _args(**kw: object) -> argparse.Namespace:
    base: dict[str, object] = {
        "apps": ["rofi"],
        "workers": 2,
        "max_bytes": 1 << 30,
        "seed_dir": EMPTY_SEED_DIR,
        "dry_run": False,
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
        seed_dir = _seed_dir_with("rofi", binary + "/bin/rofi")
        with mock.patch.object(
            record, "scan", return_value={"rofi": list(files)}
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            return _run_record(_args(state=self.state, seed_dir=seed_dir))

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
        # EMPTY_SEED_DIR has no "rofi" file, so seed_stamp is None: the same
        # case as an app whose real binary could not be resolved.
        with mock.patch.object(
            record, "scan", return_value={"rofi": ["/a"]}
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
        seed_dir = _seed_dir_with("rofi", ROOT_A + "/bin/rofi")
        with mock.patch.object(
            record, "scan", return_value={"rofi": ["/a"]}
        ), mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            _run_record(_args(state=state, seed_dir=seed_dir))
            with mock.patch.object(manifest, "save") as saver:
                out = _run_record(_args(state=state, seed_dir=seed_dir))
        saver.assert_not_called()
        self.assertIn("unchanged", out)

    def test_a_new_path_still_saves(self) -> None:
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        seed_dir = _seed_dir_with("rofi", ROOT_A + "/bin/rofi")
        with mock.patch.object(
            manifest, "prune", side_effect=lambda m, **_kw: m
        ):
            with mock.patch.object(
                record, "scan", return_value={"rofi": ["/a"]}
            ):
                _run_record(_args(state=state, seed_dir=seed_dir))
            with mock.patch.object(
                record, "scan", return_value={"rofi": ["/b"]}
            ):
                out = _run_record(_args(state=state, seed_dir=seed_dir))
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
    """I2: the headline must be able to fail.

    mincore always reports 100% on /nix, so warm/status report bytes read
    from real block devices (warm.device_read_bytes) instead of residency.
    """

    def _file(self, size: int) -> str:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "f.bin")
        with open(p, "wb") as f:
            f.write(os.urandom(4096) * (size // 4096))
        return p

    def test_off_disk_bytes_and_cold_pct_are_reported(self) -> None:
        a, b = self._file(2 << 20), self._file(2 << 20)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a, b]}, {})
        args = _args(state=state, apps=["rofi"])
        buf = io.StringIO()
        with mock.patch.object(
            warm, "device_read_bytes", side_effect=[0, 3 << 20]
        ):
            with contextlib.redirect_stdout(buf):
                self.assertEqual(main.cmd_warm(args), 0)
        out = buf.getvalue()
        self.assertIn("2 files, 4.0 MB of 4.0 MB planned in", out)
        self.assertIn("3.0 MB off disk (75.0% was cold)", out)

    def test_zero_bytes_read_does_not_divide_by_zero(self) -> None:
        """Planned > 0 but the actual read comes back 0 (e.g. every planned
        file vanished between plan_reads and warm -- a TOCTOU race, not the
        "nothing was ever planned" case that cmd_warm now refuses outright).
        """
        a = self._file(4096)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a]}, {})
        args = _args(state=state, apps=["rofi"])
        buf = io.StringIO()
        with mock.patch.object(warm, "warm", return_value=0):
            with contextlib.redirect_stdout(buf):
                self.assertEqual(main.cmd_warm(args), 0)
        self.assertIn("0.0% was cold", buf.getvalue())

    def test_empty_plan_is_refused_not_reported_as_success(self) -> None:
        """The bug this module shipped with: 0 files, 0.0 MB, exit 0."""
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": []}, {})
        args = _args(state=state, apps=["rofi"])
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            rc = main.cmd_warm(args)
        self.assertNotEqual(rc, 0)
        self.assertIn("refusing", buf.getvalue())

    def test_negative_device_delta_is_clamped_to_zero(self) -> None:
        """Another process's reads can race the counter down; never print negative MB."""
        a = self._file(4096)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a]}, {})
        args = _args(state=state, apps=["rofi"])
        buf = io.StringIO()
        with mock.patch.object(
            warm, "device_read_bytes", side_effect=[10 << 20, 5 << 20]
        ):
            with contextlib.redirect_stdout(buf):
                main.cmd_warm(args)
        self.assertIn("0.0 MB off disk", buf.getvalue())

    def test_warns_when_read_falls_materially_short_of_planned(self) -> None:
        """I1: warm() used to just re-sum planned sizes before the fork, so
        `read` could never fall short of `planned` even when every open()
        failed. Now that warm() reports what the forked readers actually
        got, cmd_warm must say so when the gap is large.
        """
        a = self._file(4 << 20)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a]}, {})
        args = _args(state=state, apps=["rofi"])
        out = io.StringIO()
        err = io.StringIO()
        with mock.patch.object(warm, "warm", return_value=0):
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = main.cmd_warm(args)
        self.assertEqual(rc, 0)
        self.assertIn("WARNING", err.getvalue())
        self.assertIn("planned", err.getvalue())

    def test_no_warning_when_read_is_close_to_planned(self) -> None:
        a = self._file(4 << 20)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a]}, {})
        args = _args(state=state, apps=["rofi"])
        out = io.StringIO()
        err = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            main.cmd_warm(args)
        self.assertNotIn("WARNING", err.getvalue())

    def test_headline_reports_bytes_actually_read_on_a_partial_shortfall(self) -> None:
        """N2: the headline used to print _mb(planned) unconditionally while
        rate/cold_pct were derived from read. A shortfall too small to trip
        the WARNING (read >= planned // 2) used to print a healthy-looking
        planned figure with no signal at all; the headline must show what
        was actually read.
        """
        a = self._file(4 << 20)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a]}, {})
        args = _args(state=state, apps=["rofi"])
        buf = io.StringIO()
        # 60% of the 4 MB planned: above the planned // 2 WARNING floor, so
        # this must be visible only via the headline's own read figure.
        with mock.patch.object(warm, "warm", return_value=(4 << 20) * 3 // 5):
            with contextlib.redirect_stdout(buf):
                rc = main.cmd_warm(args)
        self.assertEqual(rc, 0)
        out = buf.getvalue()
        self.assertIn("2.4 MB of 4.0 MB planned", out)
        self.assertNotIn("4.0 MB in", out)

    def test_status_reports_file_count_and_size_without_a_percentage(self) -> None:
        a, b = self._file(8192), self._file(8192)
        state = os.path.join(tempfile.mkdtemp(), "manifest.json")
        manifest.save(state, {"rofi": [a, b]}, {})
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            main.cmd_status(_args(state=state))
        out = buf.getvalue()
        self.assertIn(f"2 files, {main._mb(16384)}", out)
        self.assertIn("warm", out)
        self.assertNotIn("%", out)


class TestLoadSeed(unittest.TestCase):
    def test_reads_the_build_time_seed(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "rofi"), "w") as f:
                f.write("/nix/store/aaa-rofi/bin/rofi\n/nix/store/bbb-glib/lib/x.so\n")
            self.assertEqual(
                main.load_seed(d, "rofi"),
                ["/nix/store/aaa-rofi/bin/rofi", "/nix/store/bbb-glib/lib/x.so"],
            )

    def test_missing_seed_is_empty_not_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(main.load_seed(d, "nope"), [])

    def test_stamp_is_the_store_root_of_the_first_line(self) -> None:
        """The first line is the real binary, so it carries the generation."""
        # A store hash is exactly 32 chars of the nix base32 alphabet -- the
        # brief's shorthand "aaa" does not satisfy STORE_ROOT_RE, so this uses
        # a full 32-char hash, matching the convention in test_unwrap.py.
        hsh = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "rofi"), "w") as f:
                f.write(
                    f"/nix/store/{hsh}-rofi-2.0.0/bin/rofi\n"
                    f"/nix/store/{hsh}-x/l.so\n"
                )
            self.assertEqual(
                main.seed_stamp(d, "rofi"), f"/nix/store/{hsh}-rofi-2.0.0"
            )


class TestDryRun(unittest.TestCase):
    def test_dry_run_reports_bytes_per_app_and_reads_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f")
            with open(p, "w") as f:
                f.write("x" * 100)
            seeds = os.path.join(d, "seeds")
            os.makedirs(seeds)
            with open(os.path.join(seeds, "rofi"), "w") as f:
                f.write(p + "\n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = main.main(["--seed-dir", seeds, "--apps", "rofi",
                                "--state", os.path.join(d, "m.json"),
                                "--dry-run", "warm"])
            self.assertEqual(rc, 0)
            self.assertIn("rofi 100", out.getvalue())

    def test_warm_refuses_an_empty_plan(self) -> None:
        """0 files must be a loud failure, not a success.

        It printed "0 files, 0.0 MB" and returned 0 for months.
        """
        with tempfile.TemporaryDirectory() as d:
            seeds = os.path.join(d, "seeds")
            os.makedirs(seeds)
            rc = main.main(["--seed-dir", seeds, "--apps", "rofi",
                            "--state", os.path.join(d, "m.json"), "warm"])
            self.assertNotEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
