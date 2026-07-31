#!/usr/bin/env bash
# Which processes currently hold a camera open, as ONE JSON line, polled by the
# bar's CaptureService while unlocked:
#
#   {"cameras": [{"device": "/dev/video0", "deviceName": "Integrated Camera",
#                 "pid": 5230, "comm": "firefox-devedit",
#                 "name": "firefox-devedition-bin"}]}
#
# `cameras` is null when the scan could NOT run, and [] when it ran and found
# nothing. null and [] are DIFFERENT answers: [] means "asked, no camera in
# use", null means "could not ask" and the bar shows a warning tint instead of
# implying safety.
#
# ALWAYS EXITS 0, deliberately. Lib.CommandPoll treats a nonzero exit as a
# failed poll and KEEPS THE LAST-GOOD VALUE, so a probe that failed by exit code
# would leave a stale "no camera in use" on screen. Failure travels in the JSON.
#
# Why /proc and not PipeWire: Firefox opens cameras through V4L2 directly and
# its PipeWire video nodes stay `suspended` for the whole call, so a PipeWire
# check is blind to the most common camera consumer on this machine. The fd scan
# also covers PipeWire-based users, because wireplumber must itself hold the fd
# to serve them, and it releases the fd when idle.
#
# Why `find -lname` and not a shell loop: the obvious loop forks a readlink per
# fd and measured 16s on this machine, longer than the poll interval. find does
# the readlink in-process and measures ~53ms. Do not "simplify" this back.
#
# `comm` (/proc/PID/comm) is kernel-truncated to 15 characters, so
# "firefox-devedition-bin" shows up as "firefox-devedit". `name` is the
# basename of argv[0] read from /proc/PID/cmdline instead, which is not
# truncated; it falls back to `comm` when cmdline is unreadable or empty
# (kernel threads have no cmdline). Both fields ship so the caller can pick.
#
# Limitation: other users' /proc/PID/fd entries are unreadable, so a capture by
# a root or other-user process is invisible here. This UNDER-counts and never
# over-counts, which is the correct direction; running privileged is a worse
# trade.
#
# Reads only. Writes nothing.
set -uo pipefail

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    # JSON forbids raw control bytes (<0x20) unescaped. /proc/PID/comm is
    # settable by any process via prctl(PR_SET_NAME) and the v4l2 driver
    # name is hardware/driver-supplied, so either may contain them. Strip
    # rather than \u00XX-escape: simpler, and a dropped byte in a label is
    # harmless. (NUL cannot appear here: bash variables cannot hold it.)
    s=$(LC_ALL=C tr -d '\001-\037' <<< "$s")
    printf '%s' "$s"
}

cameras=null

if command -v find >/dev/null 2>&1; then
    # Capability self-test, on a controlled fixture rather than the real
    # scan: `command -v find` only proves a binary named find exists, not
    # that it understands -lname/-printf the way we need (a shadowing
    # non-GNU find could silently misbehave). We deliberately do NOT gate on
    # the real /proc scan's own exit status for this: GNU find routinely
    # exits nonzero when scanning /proc/*/fd purely from `Permission denied`
    # on other users' entries (see Limitation above) -- expected, and
    # already tolerated by discarding stderr -- even though it succeeds for
    # every directory it can read. Gating cameras=null on that exit status
    # was tried and measured: it reports null on EVERY normal poll on this
    # multi-user machine, never [], which is worse than the bug it would
    # fix. This self-test proves capability without that false positive.
    #
    # The fixture is /proc/self/fd, not a scratch file: it always has at
    # least fds 0/1/2 as symlinks already, so the same -lname/-printf
    # discrimination is available with zero writes -- no mktemp, no
    # ln -s, nothing to clean up.
    #
    # The SHAPE of the output is asserted, not merely its presence. A stub
    # that prints anything at all and exits 0 passed a non-empty test, and
    # the scan below then produced "[]" -- the exact false all-clear the
    # null-vs-[] distinction exists to prevent. Every line of a working
    # '%h %l' run over /proc/self/fd must start with "/proc/self/fd ".
    find_capable=0
    got=$(find /proc/self/fd -lname '*' -printf '%h %l\n' 2>/dev/null | head -1)
    case "$got" in
        "/proc/self/fd "?*) find_capable=1 ;;
    esac

    if [ "$find_capable" -eq 1 ]; then
        entries=""
        sep=""
        # Must be initialised before the loop: `set -u` aborts on the
        # first `case " $seen "` if it is still unset.
        seen=""
        # '%h %l' prints "/proc/<pid>/fd /dev/videoN". A process holding
        # the same device on several fds appears once per fd, so dedup on
        # the pid+device pair below.
        while read -r dir dev; do
            [ -z "$dir" ] && continue
            pid=${dir#/proc/}
            pid=${pid%%/*}
            case "$pid" in
                '' | *[!0-9]*) continue ;;
            esac

            key="$pid $dev"
            case " $seen " in
                *" $key "*) continue ;;
            esac
            seen="$seen $key"

            comm=""
            [ -r "/proc/$pid/comm" ] && read -r comm < "/proc/$pid/comm"

            devname=""
            base=${dev##*/}
            [ -r "/sys/class/video4linux/$base/name" ] && read -r devname < "/sys/class/video4linux/$base/name"

            # argv[0] via cmdline (NUL-separated) is not kernel-truncated
            # like comm; fall back to comm when cmdline is unreadable or
            # empty (e.g. kernel threads have no cmdline at all).
            argv0=""
            if [ -r "/proc/$pid/cmdline" ]; then
                IFS= read -r -d '' argv0 < "/proc/$pid/cmdline" 2>/dev/null
            fi
            if [ -n "$argv0" ]; then
                procname=${argv0##*/}
            else
                procname=$comm
            fi

            entries="$entries$sep{\"device\": \"$(json_escape "$dev")\", \"deviceName\": \"$(json_escape "$devname")\", \"pid\": $pid, \"comm\": \"$(json_escape "$comm")\", \"name\": \"$(json_escape "$procname")\"}"
            sep=", "
        done < <(find /proc/[0-9]*/fd -lname '/dev/video*' -printf '%h %l\n' 2>/dev/null)
        cameras="[$entries]"
    fi
fi

printf '{"cameras": %s}\n' "$cameras"
exit 0
