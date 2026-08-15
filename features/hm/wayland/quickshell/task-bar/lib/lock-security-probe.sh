#!/usr/bin/env bash
# Volatile lock-security state as ONE JSON line, polled by lock/Lock.qml only
# while the session is locked:
#
#   {"casts": 0, "cams": 0, "mics": 0, "sessions": 1, "otherUsers": 0,
#    "uptimeSec": 254000}
#
# `casts` is the number of live SCREEN captures, or null when it could not be
# determined. null and 0 are DIFFERENT answers and the lock renders them
# differently: 0 means "asked, nothing is capturing", null means "could not ask"
# and shows a warning instead of implying safety.
#
# `cams` and `mics` are the camera and microphone equivalents. They are a
# SEPARATE signal from `casts` and must never be presented as screen-share
# detection -- a browser sharing one of its own TABS produces no `casts` at all
# (see the blind spot in docs/lock-security-signals/spec.md), and the device
# rows only narrow that gap because a call which tab-shares usually also has a
# mic open. They do not close it.
#
# ALWAYS EXITS 0, deliberately. Lib.CommandPoll treats a nonzero exit as a failed
# poll and KEEPS THE LAST-GOOD VALUE, so a probe that failed by exit code would
# leave a stale "nothing is capturing" on screen. Failure must travel inside the
# JSON instead.
#
# Reads only; writes nothing.
set -uo pipefail

casts=null
mics=null
if command -v pw-dump >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    dump=$(pw-dump 2>/dev/null) || dump=""
    if [ -n "$dump" ]; then
        # A screen capture is a Video/Source node that is NOT a camera. Excluding
        # cameras is more robust than guessing the portal's node naming: the
        # built-in webcams are identifiable by device.api/media.role/factory.name.
        # The ? operators and tostring guards ensure a single malformed node does not
        # abort the traversal and hide a real capture that appears later in the array.
        n=$(printf '%s' "$dump" | jq '[ .[]? | select((.type? // "") == "PipeWire:Interface:Node") | (.info.props? // {})
              | select(((.["media.class"]? // "") | tostring) | contains("Video/Source"))
              | select((.["device.api"]? // "") != "v4l2")
              | select((.["media.role"]? // "") != "Camera")
              | select((((.["factory.name"]? // "") | tostring) | startswith("api.v4l2")) | not) ] | length' 2>/dev/null) || n=""
        case "$n" in
            '' | *[!0-9]*) casts=null ;;
            *) casts=$n ;;
        esac

        # Microphone capture. media.class is matched EXACTLY, not with
        # contains(): a connected Bluetooth headset in HFP/SCO mode keeps
        # `Stream/Input/Audio/Internal` (bluez_capture_internal) and
        # `Audio/Source/Internal` nodes in the `running` state with no
        # application capturing anything. A substring match therefore pins the
        # mic row on for as long as the headset is paired -- a false positive
        # that never clears, which on a security indicator is worse than no row
        # at all because it teaches the user to ignore it. Verified live on
        # 2026-07-31: real Firefox mic capture is exactly `Stream/Input/Audio`.
        #
        # `state` gates it because the node persists while the stream is idle;
        # only `running` means audio is actually flowing.
        m=$(printf '%s' "$dump" | jq '[ .[]? | select((.type? // "") == "PipeWire:Interface:Node") | (.info? // {})
              | select(((((.props? // {})["media.class"]?) // "") | tostring) == "Stream/Input/Audio")
              | select(((.state? // "") | tostring) == "running") ] | length' 2>/dev/null) || m=""
        case "$m" in
            '' | *[!0-9]*) mics=null ;;
            *) mics=$m ;;
        esac
    fi
fi

# Camera capture, counted as the number of PROCESSES holding an open fd on a
# V4L2 device -- deliberately NOT read from PipeWire. Firefox opens cameras
# through V4L2 directly and its PipeWire video nodes stay `suspended` for the
# whole call, so a PipeWire-based check is blind to the most common camera
# consumer on this machine (verified live on 2026-07-31: Firefox held
# /dev/video0 while both v4l2 nodes read `suspended`). The fd scan also covers
# PipeWire-based users for free, because wireplumber itself must hold the fd to
# serve them -- and it releases the fd when idle, so this does not latch on.
#
# `find -lname` rather than a shell loop with readlink: the loop forks once per
# fd and measured 16s on this machine, which exceeds the poll interval. find
# does the readlink in-process and measures ~50ms.
#
# Limitation: fds of OTHER users' processes are not readable, so a capture by
# a root or other-user process is invisible here and this under-counts. It
# never over-counts, which is the wrong direction for a security signal -- but
# the alternative (running the probe privileged) is a far worse trade.
cams=null
if command -v find >/dev/null 2>&1; then
    c=$(find /proc/[0-9]*/fd -lname '/dev/video*' -printf '%h\n' 2>/dev/null | sort -u | wc -l)
    case "$c" in
        '' | *[!0-9]*) cams=null ;;
        *) cams=$c ;;
    esac
fi

sessions=0
otherUsers=0
if command -v loginctl >/dev/null 2>&1; then
    me=$(id -un)
    while read -r _sid _uid user _rest; do
        [ -z "$user" ] && continue
        sessions=$((sessions + 1))
        [ "$user" != "$me" ] && otherUsers=$((otherUsers + 1))
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
fi

uptimeSec=0
if [ -r /proc/uptime ]; then
    read -r up _ < /proc/uptime
    up=${up%%.*}
    case "$up" in
        '' | *[!0-9]*) uptimeSec=0 ;;
        *) uptimeSec=$up ;;
    esac
fi

printf '{"casts": %s, "cams": %s, "mics": %s, "sessions": %d, "otherUsers": %d, "uptimeSec": %d}\n' \
    "$casts" "$cams" "$mics" "$sessions" "$otherUsers" "$uptimeSec"
exit 0
