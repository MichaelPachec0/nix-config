"""Tests for wrapper resolution and the ldd seed."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import unittest

import resolve

HASH = "fsakzlw63avfvkanzzvrzmylzs60qxwa"
OTHER = "7mbvdxzcg00bqnyz13r6yg2n6lncpl52"


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


class TestLddClosure(unittest.TestCase):
    def test_parses_store_paths_from_ldd_output(self) -> None:
        d = tempfile.mkdtemp()
        lib = os.path.join(d, "libc.so.6")
        open(lib, "w", encoding="utf-8").close()
        out = f"\tlibc.so.6 => {lib} (0x00007f00)\n\tlinux-vdso.so.1 (0x00007fff)\n"

        def fake_run(*_a: object, **_k: object) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args=[], returncode=0, stdout=out, stderr="")

        self.assertEqual(resolve.ldd_closure("/bin/x", run=fake_run), [os.path.realpath(lib)])

    def test_ldd_failure_is_empty(self) -> None:
        def boom(*_a: object, **_k: object) -> subprocess.CompletedProcess[str]:
            raise OSError("no ldd")

        self.assertEqual(resolve.ldd_closure("/bin/x", run=boom), [])


if __name__ == "__main__":
    unittest.main()
