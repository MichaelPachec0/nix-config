#!/usr/bin/env bash
# Every file the greeter ships must be tracked by git.
#
# WHY THIS EXISTS
#
# pkgs/qs-greeter/default.nix builds from `src = ./greeter`, and a flake
# copies only what git knows about. An untracked file under greeter/ is
# therefore present for every dev test (they read the repo directly) and
# ABSENT from the store package -- so the whole skin fails to instantiate in
# production while every headless suite stays green.
#
# That is not hypothetical: adding widgets/XpFlag.qml and forgetting to
# `git add` it produced exactly that. All nine dev suites passed; the VM
# check failed with
#
#   widgets/XpFlag.qml[-1:-1]: File not found
#   Type Kit.XpFlag unavailable
#   ... skin failed to instantiate
#
# It is the same shape as the bare-singleton bug the VM check was added for
# -- the dev path and the production path reach the same code differently --
# and it costs a multi-minute VM boot to discover. This check costs
# milliseconds, so it belongs in front of that, not behind it.
#
# Also covers dev/tests/xp-kit/, whose committed relative symlinks are what
# let the headless suites import the skin at all: an untracked symlink there
# breaks a fresh clone rather than the store package, which is a slower and
# more confusing failure than this one.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  echo "tracked-files SKIP: not a git repository (nothing to check)"
  exit 0
fi

overall=0

check_dir() {
  local label="$1" dir="$2" consequence="$3"
  [ -d "$root/$dir" ] || return 0

  # -z/--others --exclude-standard lists files git does not track and would
  # not ignore -- exactly the set that silently vanishes from the store
  # package. Ignored files are correctly excluded: they are not shipped and
  # are not meant to be.
  local untracked
  untracked="$(git -C "$root" ls-files --others --exclude-standard -- "$dir")"

  if [ -n "$untracked" ]; then
    echo "FAIL: untracked files under $label"
    echo "      $consequence"
    printf '  %s\n' $untracked
    echo "      fix: git add the paths above"
    overall=1
  fi
}

# Pathspecs are relative to the -C directory ($root, i.e. pkgs/qs-greeter),
# NOT to the repository root. Passing repo-relative paths here matches
# nothing, which makes this check pass unconditionally -- caught by
# mutation-testing it (touch an untracked file, confirm it FAILS) rather
# than by reading it, because a check that cannot fail looks identical to a
# check that is satisfied.
check_dir "greeter/ (shipped)" "greeter" \
  "these will be MISSING from the store package (src = ./greeter copies only git-tracked files):"
check_dir "dev/tests/xp-kit/ (import shims)" "dev/tests/xp-kit" \
  "these will be missing from a fresh clone, so the headless suites will fail there but pass here:"

if [ "$overall" -eq 0 ]; then
  echo "tracked-files PASS: everything under greeter/ and xp-kit/ is tracked"
fi

exit "$overall"
