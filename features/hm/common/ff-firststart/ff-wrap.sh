# PATH shim for firefox-devedition. Captures each launch's stdout+stderr, which
# otherwise goes to the compositor and is lost -- Hyprland does not log child
# stderr, so a profile error firefox prints is unrecoverable without this.
#
# Execs the real binary at its exact store path. That is load-bearing: firefox
# pins its install location in compatibility.ini (LastPlatformDir), so a shim
# that changed the resolved path would trigger an upgrade pass (startupCache
# rebuild, compatibility.ini rewrite) and manufacture the slow first start this
# harness exists to measure.
#
# FIREFOX_BIN and FF_FS_DIR are prepended by the nix module.

# Nothing here may stop firefox from starting, so the instrumentation runs
# without errexit and every probe falls back to a literal.
set +o errexit

RUN="$FF_FS_DIR/runs/$(cat /proc/sys/kernel/random/boot_id)"

# Instrumentation is best effort: every path through this script must end in
# an exec of $FIREFOX_BIN. set +o errexit above does not save us here -- an
# unredirected `exec ... >>"$LOG"` whose directory does not exist prints the
# redirection error and falls off the end WITHOUT running firefox, because
# exec of an ordinary command is not a fatal special-builtin error. If the
# run directory cannot be created (disk full, quota, a read-only home during
# a suspend/resume race), skip straight to an unredirected launch instead of
# losing it.
if ! mkdir -p "$RUN/launches" 2>/dev/null; then
  exec "$FIREFOX_BIN" "$@"
fi

TS=$EPOCHREALTIME
# Count .meta only: the directory holds two files per launch.
SEQ=$(printf '%03d' "$(( $(find "$RUN/launches" -name '*.meta' 2>/dev/null | wc -l) + 1 ))")
LOG="$RUN/launches/$SEQ.log"
META="$RUN/launches/$SEQ.meta"

# Default profile per profiles.ini. Section-scoped: Path= alone would match
# whichever profile happened to be listed first.
profile_dir() {
  local root="$HOME/.mozilla/firefox"
  local p
  p=$(awk -F= '
    /^\[/      { path=""; def=0 }
    /^Path=/   { path=$2 }
    /^Default=1/ { def=1 }
    def && path { print path; exit }
  ' "$root/profiles.ini" 2>/dev/null)
  [ -n "$p" ] && printf '%s/%s' "$root" "$p"
}

# Main firefox instances, not content children. comm is NOT a valid
# discriminator here: exec -a preserves argv[0] as this shim's own basename
# all the way through the launcher chain, so the shim's own process AND a
# real firefox both truncate (comm caps at 15 chars) to the identical
# "firefox-devedit" -- the old comm check counted this shell plus its own
# exit-watcher subshell below on EVERY launch, firefox running or not.
# /proc/<pid>/exe is not ambiguous: the kernel resolves it to the actual
# binary that was execve'd, not argv[0]. Firefox's launcher re-execs itself
# with "-bin" appended (a stable convention of the launcher, not particular
# to this build), so REAL_BIN is derived from FIREFOX_BIN's own basename
# rather than hardcoding a product name.
#
# MEASURED: `$(cat "$f")` here forks ~400 times and costs 981ms. The read
# builtin does the same work in 10ms. exe can't be read the same way -- an
# open() on a /proc/*/exe magic symlink returns the target BINARY's bytes,
# not its path text, and bash has no builtin for readlink(2). `[[ a -ef b ]]`
# sidesteps that: it stats both sides (no fork, no read) and compares
# device+inode, so the per-PID cost stays a syscall pair, not a subprocess.
count_main() {
  local n=0 f real_bin
  local store_root="${FIREFOX_BIN%/bin/*}"
  # Parameter expansion, not `basename`: this runs once per launch, not once
  # per PID, so a single fork here would not blow the budget -- but there is
  # no reason to pay for one when the shell can strip the leading path itself.
  local real_name="${FIREFOX_BIN##*/}-bin"
  # Globbing, not `readlink -f`: globbing is a bash builtin (readdir+lstat,
  # no fork), and the launcher's self-re-exec to "-bin" is not a symlink hop
  # readlink -f could follow anyway -- it happens inside the compiled
  # launcher at runtime, invisible to the filesystem.
  for real_bin in "$store_root"/lib/*/"$real_name"; do
    [ -e "$real_bin" ] || continue
    for f in /proc/[0-9]*/exe; do
      [[ $f -ef "$real_bin" ]] && n=$((n+1))
    done
    break
  done
  printf '%s' "$n"
}

PROFILE=$(profile_dir)

{
  echo "seq=$SEQ"
  echo "start_epoch=$TS"
  echo "args=$*"
  echo "pid=$$"
  echo "profile=$PROFILE"
  echo "prior_instances=$(count_main)"
  echo "lock_before=$(readlink "$PROFILE/lock" 2>/dev/null || echo none)"
  echo "parentlock_before=$([ -e "$PROFILE/.parentlock" ] && echo present || echo absent)"
  echo "recovery_before=$([ -e "$PROFILE/sessionstore-backups/recovery.jsonlz4" ] && echo present || echo absent)"
  systemctl --user show store-preload.service \
    -p ActiveState -p SubState -p ExecMainStartTimestamp 2>/dev/null \
    | sed 's/^/store_preload_/'
  systemctl --user show graphical-session.target \
    -p ActiveEnterTimestampMonotonic 2>/dev/null | sed 's/^/gs_/' 
  echo "uptime_s=$(cut -d' ' -f1 /proc/uptime)"
  echo "mem_available_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
  echo "real_binary=$FIREFOX_BIN"
  # Builtin arithmetic only. EPOCHREALTIME always has 6 decimals, so dropping
  # the dot yields integer microseconds. Calling out to python here would cost
  # ~40ms and defeat the point of measuring the overhead at all.
  echo "shim_overhead_us=$(( ${EPOCHREALTIME/./} - ${TS/./} ))"
} > "$META"

# exec replaces this shell, so no trap can record the exit. Watch the pid from
# a detached child instead.
(
  while kill -0 $$ 2>/dev/null; do sleep 0.25; done
  {
    echo "end_epoch=$EPOCHREALTIME"
    echo "lock_after=$(readlink "$PROFILE/lock" 2>/dev/null || echo none)"
    echo "recovery_after=$([ -e "$PROFILE/sessionstore-backups/recovery.jsonlz4" ] && echo present || echo absent)"
  } >> "$META"
) >/dev/null 2>&1 &

# Attempt the real exec directly. A failed redirection makes exec fail as an
# ordinary command rather than aborting, so `||` catches it -- and unlike a
# separate probe there is no window between the check and the open.
exec "$FIREFOX_BIN" "$@" >>"$LOG" 2>&1 || exec "$FIREFOX_BIN" "$@"
