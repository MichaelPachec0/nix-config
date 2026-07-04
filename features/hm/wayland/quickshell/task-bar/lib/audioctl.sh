#!/usr/bin/env bash
# Per-app audio routing via PipeWire metadata -- the one thing the native module
# can't do. Routing is the `target.object` metadata on the stream node:
#   audioctl.sh route <stream-node-id> <sink-node-name>  -- pin app to a device
#   audioctl.sh auto  <stream-node-id>                    -- follow the global default
# A sink's object.serial pins the stream there; -1 is what WirePlumber uses for
# "follow the default sink" (auto). pw-metadata parses a leading "-1" as an
# option, so it is passed after "--". Fire-and-forget: no fragile control channel
# here (contrast btinfo.sh / RFCOMM), so no timeout/cache/recovery.
set -u
mode="${1:-}"

# `targets`: report each output stream's current selection as "<stream-id>=<x>"
# where <x> is the pinned sink's node.name, or "auto" (target.object -1/unset).
# Lets the UI highlight the selected endpoint. (Reads metadata, not node props --
# the routing target is not exposed on the node.)
if [ "$mode" = "targets" ]; then
    META=$(pw-metadata 2>/dev/null)
    pw-dump 2>/dev/null | META="$META" python3 -c "
import json, sys, re, os
meta = os.environ.get('META', '')
tgt = {}
for m in re.finditer(r\"id:(\d+) key:'target.object' value:'(-?\d+)'\", meta):
    tgt[int(m.group(1))] = int(m.group(2))
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
s2n = {}
streams = []
for o in data:
    p = ((o.get('info') or {}).get('props') or {})
    mc = p.get('media.class', '')
    if mc == 'Audio/Sink':
        try:
            s2n[int(p.get('object.serial'))] = p.get('node.name')
        except (TypeError, ValueError):
            pass
    elif mc == 'Stream/Output/Audio':
        streams.append(o.get('id'))
for sid in streams:
    t = tgt.get(sid, -1)
    print('%s=%s' % (sid, 'auto' if (t is None or t == -1) else s2n.get(t, 'auto')))
" 2>/dev/null
    exit 0
fi

sid="${2:-}"
[ -z "$sid" ] && exit 0

case "$mode" in
    auto)
        pw-metadata "$sid" target.object -- -1 Spa:Id >/dev/null 2>&1
        ;;
    route)
        sink="${3:-}"
        [ -z "$sink" ] && exit 0
        # Resolve the target sink's node.name to its object.serial (the value
        # target.object expects; the node name is not an Id).
        serial=$(pw-dump 2>/dev/null | python3 -c "
import json, sys
want = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for o in data:
    p = ((o.get('info') or {}).get('props') or {})
    if p.get('node.name') == want and p.get('media.class') == 'Audio/Sink':
        print(p.get('object.serial', ''))
        break
" "$sink" 2>/dev/null)
        [ -z "$serial" ] && exit 0
        pw-metadata "$sid" target.object "$serial" Spa:Id >/dev/null 2>&1
        ;;
esac
exit 0
