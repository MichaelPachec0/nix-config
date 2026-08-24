"""Tests for gen-seed.sh: the seed PRODUCER's line-1-is-the-real-binary
invariant.

test_main.py's TestLoadSeed hand-builds seed fixtures with the binary already
first -- that encodes the invariant a correct producer must uphold, but does
not exercise the producer. C2 was exactly this gap: `sort -u` over
[real binary] + [ldd's output] reordered the real binary away from line 1
whenever a dependency's store hash sorted lower, and nothing caught it because
every fixture in the consumer's tests started from an already-correct file.
This runs the actual shell script default.nix invokes to build each seed.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from dataclasses import dataclass, field

GEN_SEED = os.path.join(os.path.dirname(__file__), "gen-seed.sh")

# Lexicographically smaller than REAL below, so a naive `sort -u` over
# [real, dep] puts dep first -- the exact shape of the measured bug
# (fontconfig sorting before rofi/quickshell).
_DEP = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-fontconfig-2.18/lib/libfontconfig.so.1"
_REAL = "/nix/store/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-quickshell-1.0/bin/quickshell"


@dataclass
class _Result:
    returncode: int
    stderr: str
    lines: list[str] = field(default_factory=list)


def _bash() -> str:
    """Absolute path to bash. A nix build sandbox has no /usr/bin/env, so a
    stub script's shebang cannot use the usual `#!/usr/bin/env bash`."""
    found = shutil.which("bash")
    if found is None:
        raise RuntimeError("bash not found on PATH")
    return found


def _stub_ldd(bindir: str, deps: list[str]) -> None:
    """A fake `ldd` on PATH that prints deps regardless of its argument."""
    path = os.path.join(bindir, "ldd")
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"#!{_bash()}\n")
        for d in deps:
            f.write(f'echo "\t=> {d} (0x0)"\n')
    st = os.stat(path)
    os.chmod(path, st.st_mode | stat.S_IEXEC)


def _run(script: str, real: str, deps: list[str]) -> _Result:
    """Run `script real out` with a stub ldd on PATH reporting deps."""
    with tempfile.TemporaryDirectory() as d:
        _stub_ldd(d, deps)
        out = os.path.join(d, "seed")
        env = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"])
        proc = subprocess.run(
            ["bash", script, real, out],
            env=env, capture_output=True, text=True,
        )
        lines: list[str] = []
        if proc.returncode == 0:
            with open(out, encoding="utf-8") as f:
                lines = [ln.strip() for ln in f if ln.strip()]
        return _Result(proc.returncode, proc.stderr, lines)


def _run_gen_seed(real: str, deps: list[str]) -> _Result:
    return _run(GEN_SEED, real, deps)


class TestGenSeedRealBinaryIsAlwaysFirst(unittest.TestCase):
    def test_real_binary_stays_first_even_when_a_dep_sorts_earlier(self) -> None:
        result = _run_gen_seed(_REAL, [_DEP])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.lines[0], _REAL)
        self.assertIn(_DEP, result.lines)

    def test_real_binary_with_no_dependencies_still_seeds_one_line(self) -> None:
        """grep -vxF against an empty ldd output must not abort the script:
        under set -o pipefail, a `grep` that matches nothing exits 1."""
        result = _run_gen_seed(_REAL, [])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.lines, [_REAL])

    def test_a_dependency_identical_to_the_real_binary_is_not_duplicated(self) -> None:
        result = _run_gen_seed(_REAL, [_DEP, _REAL])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.lines[0], _REAL)
        self.assertEqual(result.lines.count(_REAL), 1)

    def test_guard_catches_a_reintroduced_sort_over_everything(self) -> None:
        """Regression coverage for the exact C2 bug: if gen-seed.sh is ever
        rewritten back to `{ echo real; ldd ...; } | sort -u`, the assertion
        must fail the build instead of silently shipping a seed whose stamp
        is a library.
        """
        with open(GEN_SEED, encoding="utf-8") as f:
            src = f.read()
        old = (
            'deps=$(ldd "$real" | grep -o \'/nix/store/[^ )]*\' | '
            'sort -u | grep -vxF "$real" || true)\n\n'
            '{\n'
            '  echo "$real"\n'
            '  [ -z "$deps" ] || printf \'%s\\n\' "$deps"\n'
            '} > "$out"'
        )
        new = (
            '{ echo "$real"; ldd "$real" | grep -o \'/nix/store/[^ )]*\'; } '
            '| sort -u > "$out"'
        )
        self.assertIn(old, src, "gen-seed.sh text changed; update this test's match string")
        broken_src = src.replace(old, new)

        with tempfile.TemporaryDirectory() as d:
            broken = os.path.join(d, "gen-seed-broken.sh")
            with open(broken, "w", encoding="utf-8") as f:
                f.write(broken_src)
            result = _run(broken, _REAL, [_DEP])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not the real binary", result.stderr)


if __name__ == "__main__":
    unittest.main()
