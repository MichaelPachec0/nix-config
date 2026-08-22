"""Tests for wrapper resolution and the ldd seed."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

import resolve

HASH = "fsakzlw63avfvkanzzvrzmylzs60qxwa"
OTHER = "7mbvdxzcg00bqnyz13r6yg2n6lncpl52"


class TestNormBasename(unittest.TestCase):
    def test_strips_leading_dot(self) -> None:
        self.assertEqual(resolve.norm_basename(".kitty-wrapped"), "kitty")

    def test_removes_wrapped_suffix(self) -> None:
        self.assertEqual(resolve.norm_basename("foo-wrapped"), "foo")

    def test_no_change_for_plain_name(self) -> None:
        self.assertEqual(resolve.norm_basename("rofi"), "rofi")

    def test_combined_dot_and_wrapped(self) -> None:
        self.assertEqual(resolve.norm_basename(".kitty-wrapped"), "kitty")


class TestStoreRoot(unittest.TestCase):
    def test_takes_the_package_dir(self) -> None:
        self.assertEqual(
            resolve.store_root(f"/nix/store/{HASH}-foo-1.0/bin/foo"),
            f"/nix/store/{HASH}-foo-1.0",
        )

    def test_root_itself_is_unchanged(self) -> None:
        root = f"/nix/store/{HASH}-foo-1.0"
        self.assertEqual(resolve.store_root(root), root)

    def test_different_hash_is_a_different_stamp(self) -> None:
        a = resolve.store_root(f"/nix/store/{HASH}-foo-1.0/bin/foo")
        b = resolve.store_root(f"/nix/store/{OTHER}-foo-1.0/bin/foo")
        self.assertNotEqual(a, b)

    def test_non_store_path_is_none(self) -> None:
        self.assertIsNone(resolve.store_root("/usr/bin/foo"))

    def test_malformed_hash_is_none(self) -> None:
        self.assertIsNone(resolve.store_root("/nix/store/short-foo/bin/foo"))

    def test_none_input_is_none(self) -> None:
        self.assertIsNone(resolve.store_root(None))


class TestStoreStrings(unittest.TestCase):
    def test_extracts_paths_from_binary_blob(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "wrapper")
        with open(p, "wb") as f:
            f.write(b"\x7fELF\x00\x00padding")
            f.write(f"/nix/store/{HASH}-rofi-unwrapped-2.0.0/bin/rofi".encode())
            f.write(b"\x00more\x00")
        self.assertIn(
            f"/nix/store/{HASH}-rofi-unwrapped-2.0.0/bin/rofi",
            resolve.store_strings(p),
        )

    def test_strips_trailing_quote(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "wrapper.sh")
        with open(p, "w", encoding="utf-8") as f:
            f.write(f"exec '/nix/store/{HASH}-rofi/bin/rofi'\n")
        self.assertIn(f"/nix/store/{HASH}-rofi/bin/rofi", resolve.store_strings(p))

    def test_missing_file_is_empty(self) -> None:
        self.assertEqual(resolve.store_strings("/nonexistent"), [])


class TestRealBinary(unittest.TestCase):
    def _wrapper_pointing_at(self, target: str, name: str) -> str:
        d = tempfile.mkdtemp()
        p = os.path.join(d, name)
        with open(p, "wb") as f:
            f.write(b"\x7fELF" + target.encode() + b"\x00")
        os.chmod(p, 0o755)
        return p

    def test_resolves_wrapper_to_real_binary(self) -> None:
        d = tempfile.mkdtemp()
        real = os.path.join(d, "rofi")
        with open(real, "wb") as f:
            f.write(b"\x7fELF real")
        os.chmod(real, 0o755)
        wrapper = self._wrapper_pointing_at(real, "rofi")
        got = resolve.real_binary(
            "rofi", which=lambda _a: wrapper, strings=lambda _p: [real]
        )
        self.assertEqual(got, os.path.realpath(real))

    def test_ignores_embedded_directories(self) -> None:
        d = tempfile.mkdtemp()
        datadir = os.path.join(d, "share")
        os.makedirs(datadir)
        wrapper = self._wrapper_pointing_at(datadir, "rofi")
        # Only a directory is embedded, so the wrapper itself is the answer.
        got = resolve.real_binary(
            "rofi", which=lambda _a: wrapper, strings=lambda _p: [datadir]
        )
        self.assertEqual(got, os.path.realpath(wrapper))

    def test_missing_app_returns_none(self) -> None:
        self.assertIsNone(resolve.real_binary("nope", which=lambda _a: None))

    def test_resolves_wrapped_candidate(self) -> None:
        d = tempfile.mkdtemp()
        wrapped = os.path.join(d, ".kitty-wrapped")
        with open(wrapped, "wb") as f:
            f.write(b"\x7fELF wrapped")
        os.chmod(wrapped, 0o755)
        wrapper = self._wrapper_pointing_at(wrapped, "kitty")
        got = resolve.real_binary(
            "kitty", which=lambda _a: wrapper, strings=lambda _p: [wrapped]
        )
        self.assertEqual(got, os.path.realpath(wrapped))


class TestLddClosure(unittest.TestCase):
    def test_parses_store_paths_from_ldd_output(self) -> None:
        d = tempfile.mkdtemp()
        lib = os.path.join(d, "libc.so.6")
        open(lib, "w", encoding="utf-8").close()
        out = f"\tlibc.so.6 => {lib} (0x00007f00)\n\tlinux-vdso.so.1 (0x00007fff)\n"

        def fake_run(*_a: object, **_k: object) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args=[], returncode=0, stdout=out, stderr="")

        with mock.patch.object(resolve, "STORE_PREFIX", "/"):
            self.assertEqual(resolve.ldd_closure("/bin/x", run=fake_run), [os.path.realpath(lib)])

    def test_rejects_non_store_paths(self) -> None:
        d = tempfile.mkdtemp()
        lib = os.path.join(d, "libc.so.6")
        open(lib, "w", encoding="utf-8").close()
        out = f"\tlibc.so.6 => {lib} (0x00007f00)\n"

        def fake_run(*_a: object, **_k: object) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args=[], returncode=0, stdout=out, stderr="")

        self.assertEqual(resolve.ldd_closure("/bin/x", run=fake_run), [])

    def test_ldd_failure_is_empty(self) -> None:
        def boom(*_a: object, **_k: object) -> subprocess.CompletedProcess[str]:
            raise OSError("no ldd")

        self.assertEqual(resolve.ldd_closure("/bin/x", run=boom), [])


if __name__ == "__main__":
    unittest.main()
