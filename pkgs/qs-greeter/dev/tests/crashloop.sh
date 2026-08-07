#!/usr/bin/env bash
# Test crash-loop counting in isolation: no compositor, no quickshell.
# QSG_QS_CMD and QSG_FALLBACK_CMD are test seams the wrapper honors.
#
# Runs the PACKAGED binary, not the raw wrapper/qs-greeter-run.sh: this
# used to invoke the raw script directly, but pkgs.qs-greeter's
# writeShellApplication injects `set -o errexit -o nounset -o pipefail`
# above whatever the script itself declares (`set -uo pipefail`, errexit
# deliberately off) -- so the suite was proving the raw script's behavior,
# not the shipped one's. Verified by hand before this rewrite that the
# observable behavior is identical either way (the one place errexit could
# matter -- the final `"$@" | tee | systemd-cat` pipeline failing when the
# launched qs crashes -- aborts the script immediately under errexit
# instead of falling through to the explicit `exit "$status"` line, but
# either way the process exits nonzero and the crash counter is not reset,
# so the two paths are indistinguishable from outside), but "identical by
# inspection" is exactly the gap this rewrite closes: now it is identical
# by assertion. `nix build` of the greeter package is allowed under this
# fix's own constraints (unlike nixos-rebuild or the VM check), so this
# builds pkgs.qs-greeter.wrapper and pkgs.qs-greeter.sessionsParse fresh
# each run the same way fonts-eval.sh's `nix eval` already reaches into
# the same flake for the same nixosConfigurations.thanatos.pkgs.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

echo "building the packaged wrapper + sessions-parse..." >&2
wrapper_out="$(nix build --impure --no-link --print-out-paths --expr \
  '(builtins.getFlake (toString "'"$root"'")).nixosConfigurations.thanatos.pkgs.qs-greeter.wrapper' \
  2>/dev/null | tail -n1)"
parse_out="$(nix build --impure --no-link --print-out-paths --expr \
  '(builtins.getFlake (toString "'"$root"'")).nixosConfigurations.thanatos.pkgs.qs-greeter.sessionsParse' \
  2>/dev/null | tail -n1)"
if [ -z "$wrapper_out" ] || [ ! -x "$wrapper_out/bin/qs-greeter-run" ]; then
  echo "CRASHLOOP-TEST FAIL: nix build of the packaged wrapper did not produce a binary"
  exit 1
fi
if [ -z "$parse_out" ] || [ ! -x "$parse_out/bin/sessions-parse" ]; then
  echo "CRASHLOOP-TEST FAIL: nix build of the packaged sessions-parse did not produce a binary"
  exit 1
fi
run="$wrapper_out/bin/qs-greeter-run"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
total=0
check() {
  local name="$1" got="$2" want="$3"
  total=$((total + 1))
  if [ "$got" = "$want" ]; then pass=$((pass + 1))
  else echo "CRASHLOOP-TEST CASE FAIL: $name got=$got want=$want"; fi
}

export QSG_STATE_DIR="$tmp/run"
export QSG_LOG_DIR="$tmp/log"
export QSG_LOG_KEEP=3
export QSG_LOG_ARGS=""
export QSG_JOURNAL=0
export QSG_THRESHOLD=3
export QSG_WINDOW=120
export QSG_CONFIG="$tmp/fake-config"
export QSG_SESSIONS_DIR="$here/fixtures/wayland-sessions"
export QSG_FILTER=uwsm
export QSG_EXTRA_JSON='[]'
export QSG_SHELLS_JSON='[]'
export QSG_TTY_HINT=2
export QSG_SHOW_LOG=0
export QSG_NOW=1000
export QSG_FALLBACK_CMD="echo FALLBACK-ENGAGED"
# The packaged binary is a single-script writeShellApplication (see
# default.nix's own comment on why): dirname "$0" no longer finds
# sessions-parse.sh next to it, so QSG_PARSE must be set explicitly here
# exactly as qs-greeter.nix's real wrapperPackage sets it.
export QSG_PARSE="$parse_out/bin/sessions-parse"

# a "crashing" greeter
export QSG_QS_CMD="false"
out1="$("$run" 2>&1)"; check "firstCrashRuns" "$(echo "$out1" | grep -c FALLBACK-ENGAGED)" "0"
out2="$("$run" 2>&1)"; check "secondCrashRuns" "$(echo "$out2" | grep -c FALLBACK-ENGAGED)" "0"
out3="$("$run" 2>&1)"; check "thirdCrashRuns" "$(echo "$out3" | grep -c FALLBACK-ENGAGED)" "0"
out4="$("$run" 2>&1)"; check "fourthEngagesFallback" "$(echo "$out4" | grep -c FALLBACK-ENGAGED)" "1"

# the fallback must NOT exit non-zero: exiting returns control to greetd, which
# restarts sway, which re-enters the loop.
"$run" >/dev/null 2>&1; check "fallbackExitsZero" "$?" "0"

# outside the window, the count ages out
export QSG_NOW=9999
out5="$("$run" 2>&1)"; check "windowExpiry" "$(echo "$out5" | grep -c FALLBACK-ENGAGED)" "0"

# a successful launch truncates the counter
rm -rf "$tmp/run"
export QSG_NOW=2000
export QSG_QS_CMD="true"
"$run" >/dev/null 2>&1
check "successTruncates" "$(wc -l <"$tmp/run/crashes" 2>/dev/null || echo 0)" "0"

# sessions.json is written before the greeter starts
check "sessionsWritten" "$(jq -r '.[0].name' "$tmp/run/sessions.json")" "Hyprland (uwsm-managed)"

# log pruning keeps only QSG_LOG_KEEP files
export QSG_QS_CMD="true"
for i in 1 2 3 4 5; do export QSG_NOW=$((3000 + i)); "$run" >/dev/null 2>&1; done
check "logsPruned" "$(find "$tmp/log" -name 'greeter-*.log' | wc -l)" "3"

# --- the REAL fallback branch (no QSG_FALLBACK_CMD test seam) ------------
# Every case above drives the fallback through the test seam, which never
# exercises the actual foot/swaynag/infinite-loop branch at all. That
# branch cannot be run for real here -- it launches interactive UI and then
# blocks forever on purpose (`while :; do sleep 3600; done`, so that
# returning control to greetd never re-enters the loop) -- but the exact
# commands it constructs, and the fact that it blocks rather than exiting,
# ARE checkable without a compositor: put fake `foot`/`swaynag` on PATH
# that just record their own invocation and return immediately, seed a
# crash count already past the threshold so the fallback engages on the
# very first run, and bound the whole thing with `timeout` since the real
# branch never exits on its own.
#
# Runs the RAW script here, not the packaged $run: writeShellApplication's
# preamble prepends its own runtimeInputs (which include the REAL foot and
# sway/swaynag) onto PATH from inside the packaged script, after this
# script's own PATH override has already been inherited -- so the real
# binaries would shadow these stubs for the packaged binary specifically,
# defeating the interception. The raw script injects no such override, so
# a plain PATH prepend works. This is still coverage of the shipped
# fallback LOGIC (raw and packaged run the identical script text; only the
# packaging preamble differs, and that preamble is what the crash-loop
# COUNTING assertions above already moved onto the packaged binary to
# cover) -- just not of the packaged invocation specifically, which this
# one sub-case cannot reach without rebuilding the package with fake
# runtimeInputs.
#
# What this does NOT cover, and has no automated coverage anywhere in this
# plan: that foot/swaynag actually RENDER anything, that the real TTY
# switch hint is reachable, or that clicking swaynag's Reboot/Power off
# buttons actually runs systemctl -- those need the interactive pass.
raw_run="$here/../../wrapper/qs-greeter-run.sh"
stub_bin="$tmp/stub-bin"
mkdir -p "$stub_bin"
capture="$tmp/fallback-invocations.log"
: >"$capture"
cat >"$stub_bin/foot" <<'EOF'
#!/usr/bin/env bash
echo "foot $*" >>"$CAPTURE_FILE"
exit 0
EOF
cat >"$stub_bin/swaynag" <<'EOF'
#!/usr/bin/env bash
echo "swaynag $*" >>"$CAPTURE_FILE"
exit 0
EOF
chmod +x "$stub_bin/foot" "$stub_bin/swaynag"

rm -rf "$tmp/run" "$tmp/log"
mkdir -p "$tmp/run" "$tmp/log"
export QSG_NOW=5000
# QSG_SHOW_LOG was 0 for every case above (to keep them from trying to
# launch a real foot); this sub-case is specifically about the show_log=1
# branch, so it needs to be back on.
export QSG_SHOW_LOG=1
# Three prior crashes inside the window, all still within QSG_WINDOW=120 of
# QSG_NOW=5000, so the very next run engages the fallback immediately --
# same threshold-crossing shape as "fourthEngagesFallback" above, just
# seeded directly instead of earned through three real runs.
for s in 4970 4980 4990; do printf '%s\n' "$s" >>"$tmp/run/crashes"; done
# A prior log file so `newest` (the fallback message's log-tail source)
# resolves to something real, matching a genuine crash loop's own state.
printf 'fake prior crash output\n' >"$tmp/log/greeter-4990.log"

unset QSG_FALLBACK_CMD
CAPTURE_FILE="$capture" PATH="$stub_bin:$PATH" timeout 2 "$raw_run" >/dev/null 2>&1
fallback_status=$?
export QSG_FALLBACK_CMD="echo FALLBACK-ENGAGED"
# 124 = timeout killed it, proving the branch reached `while :; do sleep
# 3600; done` and never exited on its own -- exactly the "refuses to exit"
# property fallbackExitsZero above already checks on the TEST-SEAM branch,
# now checked on the real one too.
check "realFallbackNeverExits" "$fallback_status" "124"
check "realFallbackLaunchedFoot" "$(grep -c '^foot ' "$capture" 2>/dev/null || echo 0)" "1"
check "realFallbackFootShowsTitle" "$(grep -c 'qs-greeter log' "$capture" 2>/dev/null || echo 0)" "1"
check "realFallbackLaunchedSwaynag" "$(grep -c '^swaynag ' "$capture" 2>/dev/null || echo 0)" "1"
check "realFallbackSwaynagMessage" \
  "$(grep -c 'graphical greeter failed to start 3 times' "$capture" 2>/dev/null || echo 0)" "1"
check "realFallbackSwaynagHasRebootButton" \
  "$(grep -c -- '-b Reboot systemctl reboot' "$capture" 2>/dev/null || echo 0)" "1"

if [ "$pass" = "$total" ]; then
  echo "CRASHLOOP-TEST PASS $pass/$total"
else
  echo "CRASHLOOP-TEST FAIL $pass/$total"
  exit 1
fi
