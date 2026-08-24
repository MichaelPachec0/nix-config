"""Tests for build-time wrapper resolution."""

import os
import tempfile
import unittest

import unwrap


class TestSibling(unittest.TestCase):
    def test_prefers_dot_wrapped_sibling(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            real = os.path.join(d, ".kitty-wrapped")
            open(real, "wb").write(b"\x7fELF")
            wrapper = os.path.join(d, "kitty")
            open(wrapper, "wb").write(b"\x7fELF")
            self.assertEqual(unwrap.resolve(wrapper), real)


class TestStrings(unittest.TestCase):
    def setUp(self) -> None:
        # Every test in this class points unwrap.STORE_PREFIX at a tempdir
        # that is gone by teardown; without restoring it, a later test in the
        # same discover process inherits a STORE_PREFIX pointing at a deleted
        # directory.
        self.addCleanup(setattr, unwrap, "STORE_PREFIX", unwrap.STORE_PREFIX)

    def test_falls_back_to_embedded_store_path(self) -> None:
        """rofi has no .rofi-wrapped; its real binary is another derivation."""
        with tempfile.TemporaryDirectory() as d:
            realdir = os.path.join(d, "nix", "store",
                                   "a" * 32 + "-rofi-unwrapped-2.0.0", "bin")
            os.makedirs(realdir)
            real = os.path.join(realdir, "rofi")
            open(real, "wb").write(b"\x7fELF")
            os.chmod(real, 0o755)
            wrapper = os.path.join(d, "rofi")
            open(wrapper, "wb").write(b"\x7fELF" + real.encode())
            unwrap.STORE_PREFIX = os.path.join(d, "nix", "store")
            self.assertEqual(unwrap.resolve(wrapper), real)

    def test_never_returns_a_share_path(self) -> None:
        """rofi's wrapper embeds a merged XDG_DATA_DIRS holding a tor-browser.

        Walking it is what produced the 338 MB data_files result that was
        deleted by ruling during the original build.
        """
        with tempfile.TemporaryDirectory() as d:
            share = os.path.join(d, "nix", "store",
                                 "b" * 32 + "-tor-browser", "share", "rofi")
            os.makedirs(os.path.dirname(share))
            open(share, "wb").write(b"x")
            os.chmod(share, 0o755)
            wrapper = os.path.join(d, "rofi")
            open(wrapper, "wb").write(b"\x7fELF" + share.encode())
            unwrap.STORE_PREFIX = os.path.join(d, "nix", "store")
            self.assertEqual(unwrap.resolve(wrapper), wrapper)

    def test_never_returns_itself(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            wrapper = os.path.join(d, "rofi")
            open(wrapper, "wb").write(b"\x7fELF" + wrapper.encode())
            unwrap.STORE_PREFIX = d
            self.assertEqual(unwrap.resolve(wrapper), wrapper)


if __name__ == "__main__":
    unittest.main()
