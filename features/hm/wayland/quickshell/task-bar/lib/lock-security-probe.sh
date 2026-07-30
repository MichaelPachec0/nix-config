#!/usr/bin/env bash
# Volatile lock-security state as ONE JSON line, polled by lock/Lock.qml only
# while the session is locked:
#
#   {"casts": 0, "sessions": 1, "otherUsers": 0, "uptimeSec": 254000}
#
# `casts` is the number of live SCREEN captures, or null when it could not be
# determined. null and 0 are DIFFERENT answers and the lock renders them
# differently: 0 means "asked, nothing is capturing", null means "could not ask"
# and shows a warning instead of implying safety.
#
# ALWAYS EXITS 0, deliberately. Lib.CommandPoll treats a nonzero exit as a failed
# poll and KEEPS THE LAST-GOOD VALUE, so a probe that failed by exit code would
# leave a stale "nothing is capturing" on screen. Failure must travel inside the
# JSON instead.
#
# Reads only; writes nothing.
set -uo pipefail

casts=null
if command -v pw-dump >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    dump=$(pw-dump 2>/dev/null) || dump=""
    if [ -n "$dump" ]; then
        # A screen capture is a Video/Source node that is NOT a camera. Excluding
        # cameras is more robust than guessing the portal's node naming: the
        # built-in webcams are identifiable by device.api/media.role/factory.name.
        n=$(printf '%s' "$dump" | jq '[ .[] | select(.type=="PipeWire:Interface:Node") | .info.props
              | select((.["media.class"] // "") | contains("Video/Source"))
              | select((.["device.api"] // "") != "v4l2")
              | select((.["media.role"] // "") != "Camera")
              | select(((.["factory.name"] // "") | startswith("api.v4l2")) | not) ] | length' 2>/dev/null) || n=""
        case "$n" in
            '' | *[!0-9]*) casts=null ;;
            *) casts=$n ;;
        esac
    fi
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
    uptimeSec=${up%%.*}
fi

printf '{"casts": %s, "sessions": %d, "otherUsers": %d, "uptimeSec": %d}\n' \
    "$casts" "$sessions" "$otherUsers" "$uptimeSec"
exit 0
