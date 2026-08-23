#!/usr/bin/env bash
# Regression test for ff-wrap.sh's best-effort invariant: every path through
# the script must end in an exec of $FIREFOX_BIN, even when FF_FS_DIR cannot
# be written to (disk full, quota, a read-only home during a suspend/resume
# race). Before the fix, an unchecked `mkdir -p "$RUN/launches"` fed an
# unredirected `exec "$FIREFOX_BIN" "$@" >>"$LOG"`; when the redirect target
# does not exist, bash prints the redirection error and falls off the end of
# the script WITHOUT running firefox (exec of an ordinary command is not a
# fatal special-builtin error, so `set +o errexit` does not save it either).
# That silently contradicted the file's own "nothing here may stop firefox
# from starting" comment. Reproduced independently with:
#   set +o errexit; exec /bin/echo hi >>/nonexistent-dir/out.log
# which prints only the redirection error; "hi" never appears.
#
# Usage: bash test_ff-wrap.sh path/to/ff-wrap.sh
# shellcheck disable=SC2329 # cleanup is invoked indirectly via trap
set -euo pipefail

WRAP="${1:?usage: test_ff-wrap.sh path/to/ff-wrap.sh}"

fail=0
check() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok:   %s\n' "$1"
  else
    printf 'FAIL: %s (want %q got %q)\n' "$1" "$2" "$3"
    fail=1
  fi
}

TMP="$(mktemp -d)"
cleanup() {
  # UNWRITABLE is left non-writable on purpose; restore perms so rm -rf
  # can actually remove it.
  chmod -R u+rwx "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# Stub in place of the real firefox binary: records that it ran and with
# what args, then exits, so a test failure can't hang on a real browser.
FIREFOX_STUB="$TMP/firefox-stub"
MARKER="$TMP/launched"
cat >"$FIREFOX_STUB" <<STUB
#!/usr/bin/env bash
printf 'LAUNCHED %s\n' "\$*" > "$MARKER"
STUB
chmod +x "$FIREFOX_STUB"

# ff-wrap.sh is a text fragment (readFile'd into a writeShellApplication
# after FIREFOX_BIN/FF_FS_DIR assignments), not a standalone shebang'd
# script -- reassemble it the same way the nix module does, then run that
# under a fresh bash so its trailing `exec` replaces the subshell, not this
# test process. "ff-wrap-test" as $0 (via `--`) makes "$@" inside start at
# the real argv, matching how the shim itself is invoked.
run_wrap() {
  local fs_dir="$1"
  shift
  # bash -c command_string $0 $1 $2 ...: the first word after the script
  # text becomes $0, everything after is "$@". No "--" here -- that would
  # itself be consumed as $0, one slot early.
  bash -c "
FIREFOX_BIN=$(printf '%q' "$FIREFOX_STUB")
FF_FS_DIR=$(printf '%q' "$fs_dir")
$(cat "$WRAP")
" ff-wrap-test "$@"
}

# --- unwritable FF_FS_DIR: the regression case --------------------------
UNWRITABLE="$TMP/state"
mkdir -p "$UNWRITABLE"
chmod 555 "$UNWRITABLE"   # readable+searchable, not writable: mkdir -p fails

rm -f "$MARKER"
run_wrap "$UNWRITABLE/ff-firststart" --version >/dev/null 2>&1 || true
check "unwritable FF_FS_DIR still launches firefox" \
  present "$([ -f "$MARKER" ] && echo present || echo absent)"
check "argv still reaches firefox when unwritable" \
  "LAUNCHED --version" "$(cat "$MARKER" 2>/dev/null || echo absent)"

chmod u+rwx "$UNWRITABLE"

# --- writable FF_FS_DIR: confirm the fix didn't break the normal path ---
WRITABLE="$TMP/writable-state"
rm -f "$MARKER"
run_wrap "$WRITABLE" --version >/dev/null 2>&1 || true
check "writable FF_FS_DIR still launches firefox" \
  present "$([ -f "$MARKER" ] && echo present || echo absent)"
check "argv reaches firefox on the normal path" \
  "LAUNCHED --version" "$(cat "$MARKER" 2>/dev/null || echo absent)"

RUN_COUNT=$(find "$WRITABLE/runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
check "normal path still writes a run directory" 1 "$RUN_COUNT"

# --- launches dir creatable, but $LOG itself cannot be opened -----------
# This is guard 2: mkdir -p "$RUN/launches" (guard 1) succeeds here, so only
# the final redirected exec can fail. Predict the exact path ff-wrap.sh will
# compute for $LOG (same boot_id, SEQ=001 since no .meta files exist yet)
# and pre-occupy it with a directory, so `>>"$LOG"` fails with EISDIR while
# the mkdir -p above it does not. This is the case a prior round's probe-based
# guard 2 (`if ! : >>"$LOG"; then ...`) was never exercised against: that
# probe and the real exec each open $LOG separately, so a mutation deleting
# the probe's fallback still passed every check here. The single `exec ... ||
# exec ...` line removes that gap; this case is what proves the fallback,
# not just the probe, actually fires.
LOGBLOCK="$TMP/logblock-state"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
RUNDIR="$LOGBLOCK/runs/$BOOT_ID"
mkdir -p "$RUNDIR/launches"
mkdir -p "$RUNDIR/launches/001.log"

rm -f "$MARKER"
run_wrap "$LOGBLOCK" --version >/dev/null 2>&1 || true
check "unopenable LOG still launches firefox" \
  present "$([ -f "$MARKER" ] && echo present || echo absent)"
check "argv still reaches firefox when LOG unopenable" \
  "LAUNCHED --version" "$(cat "$MARKER" 2>/dev/null || echo absent)"

exit "$fail"
