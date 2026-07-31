#!/usr/bin/env bash
# Which processes currently hold a camera open, as ONE JSON line, polled by the
# bar's CaptureService while unlocked:
#
#   {"cameras": [{"device": "/dev/video0", "deviceName": "Integrated Camera",
#                 "pid": 5230, "comm": "firefox-devedition-bin"}]}
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
# Limitation: other users' /proc/PID/fd entries are unreadable, so a capture by
# a root or other-user process is invisible here. This UNDER-counts and never
# over-counts, which is the correct direction; running privileged is a worse
# trade.
#
# Reads only; writes nothing.
set -uo pipefail

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

cameras=null
if command -v find >/dev/null 2>&1; then
    entries=""
    sep=""
    # Must be initialised before the loop: `set -u` aborts on the first
    # `case " $seen "` if it is still unset.
    seen=""
    # '%h %l' prints "/proc/<pid>/fd /dev/videoN". A process holding the same
    # device on several fds appears once per fd, so dedup on the pid+device
    # pair below.
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

        name=""
        base=${dev##*/}
        [ -r "/sys/class/video4linux/$base/name" ] && read -r name < "/sys/class/video4linux/$base/name"

        entries="$entries$sep{\"device\": \"$(json_escape "$dev")\", \"deviceName\": \"$(json_escape "$name")\", \"pid\": $pid, \"comm\": \"$(json_escape "$comm")\"}"
        sep=", "
    done < <(find /proc/[0-9]*/fd -lname '/dev/video*' -printf '%h %l\n' 2>/dev/null)
    cameras="[$entries]"
fi

printf '{"cameras": %s}\n' "$cameras"
exit 0
