#!/usr/bin/env bash
# Runs session-test.qml plus all three auth.backoff modes (backoff-test.qml,
# driven three times through the QSG_BACKOFF_ENABLE/QSG_BACKOFF_PERUSER env
# seam) and fails loudly: exit 0 only if every sub-run reports an exact
# "<TAG> PASS" line. A "<TAG> FAIL ..." line, or no result line at all
# (crash or syntax error), is a nonzero exit -- see settings-load.sh's
# check_case for the substring-match bug this guards against (it matched
# PASS and FAIL alike and exited 0 on a broken suite).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
overall=0

# MockBackend.qml's loadScenario() reads dev/scenarios/*.json via a
# synchronous XMLHttpRequest; Quickshell disables local-file XHR reads
# unless this is set, and silently returns an empty response otherwise
# (JSON.parse then throws and every scenario load is a no-op).
#
# `qs -p` does not reliably return control on Qt.quit() in this
# environment (see settings-load.sh); `timeout` bounds each run once the
# result line has had time to print.
run_qs() {
  local file="$1"
  shift
  env QML_XHR_ALLOW_FILE_READ=1 "$@" timeout 20 qs -p "$here/$file" 2>&1 || true
}

# check_case fails (nonzero, and bumps $overall) unless the output contains
# a final "<tag> [MODE] PASS n/n" summary line -- not a bare substring
# match on the tag, which matches the FAIL summary and the per-case
# "<tag> CASE FAIL: ..." diagnostics just as happily. The optional [MODE]
# accounts for backoff-test.qml's "BACKOFF-TEST DISABLED/GLOBAL/PERUSER
# PASS n/n" form.
check_case() {
  local label="$1" tag="$2" out="$3"
  echo "--- $label ---"
  echo "$out" | grep "$tag" || echo "(no $tag line -- crash or syntax error)"
  if ! echo "$out" | grep -qE "$tag( [A-Z]+)? PASS [0-9]+/[0-9]+"; then
    echo "FAIL: $label did not report a clean PASS"
    overall=1
  fi
}

out="$(run_qs session-test.qml)"
check_case "session-test.qml (scenario suite)" "SESSION-TEST" "$out"

out="$(run_qs backoff-test.qml)"
check_case "backoff-test.qml, mode=disabled (default env)" "BACKOFF-TEST" "$out"

out="$(run_qs backoff-test.qml QSG_BACKOFF_ENABLE=1 QSG_BACKOFF_FREE=0 QSG_BACKOFF_START=1 QSG_BACKOFF_MAX=4)"
check_case "backoff-test.qml, mode=global" "BACKOFF-TEST" "$out"

out="$(run_qs backoff-test.qml QSG_BACKOFF_ENABLE=1 QSG_BACKOFF_PERUSER=1)"
check_case "backoff-test.qml, mode=perUser" "BACKOFF-TEST" "$out"

exit "$overall"
