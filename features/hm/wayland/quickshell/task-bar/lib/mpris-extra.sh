#!/usr/bin/env bash
# MPRIS TrackList + Playlists access for the media popup. Quickshell's Mpris
# service is Player-only and exposes no generic D-Bus to QML, so this talks to
# the selected player over D-Bus via busctl --json and shapes the result to
# compact JSON. ncspot implements both optional interfaces; other players don't,
# so read modes return empty -> the popup hides the tabs.
#   mpris-extra.sh caps      <bus>            -> {"queue":0|1,"playlists":0|1}
#   mpris-extra.sh queue     <bus>            -> [{trackid,title,artist,length,art,current,played}]
#   mpris-extra.sh playlists <bus>            -> [{path,name,icon,active}]
#   mpris-extra.sh goto      <bus> <trackid>  -- jump to a queue entry
#   mpris-extra.sh remove    <bus> <trackid>  -- drop a queue entry
#   mpris-extra.sh activate  <bus> <path>     -- load/play a playlist
# Any D-Bus failure (interface absent, player gone) -> empty JSON / no-op, exit 0.
set -u
mode="${1:-}"
bus="${2:-}"
arg="${3:-}"
P=/org/mpris/MediaPlayer2
TL=org.mpris.MediaPlayer2.TrackList
PL=org.mpris.MediaPlayer2.Playlists

[ -z "$bus" ] && { echo "[]"; exit 0; }

case "$mode" in
    caps)
        q=0
        p=0
        timeout 3 busctl --user --json=short get-property "$bus" "$P" "$TL" Tracks >/dev/null 2>&1 && q=1
        timeout 3 busctl --user --json=short get-property "$bus" "$P" "$PL" PlaylistCount >/dev/null 2>&1 && p=1
        echo "{\"queue\":$q,\"playlists\":$p}"
        ;;
    queue)
        python3 - "$bus" <<'PY' 2>/dev/null || echo "[]"
import json, subprocess, sys
bus = sys.argv[1]
P = "/org/mpris/MediaPlayer2"
TL = "org.mpris.MediaPlayer2.TrackList"
PLAYER = "org.mpris.MediaPlayer2.Player"
def bc(*a):
    return subprocess.run(["busctl", "--user", "--json=short", *a],
                          capture_output=True, text=True, timeout=4)
def unwrap(v, d=None):
    return v.get("data", d) if isinstance(v, dict) else (v if v is not None else d)
BEFORE = 100  # played tracks to show above the current one (greyed out in the UI)
AFTER = 100   # the current track + upcoming. A context can be thousands of tracks
              # long, so both bounds keep the GetTracksMetadata fetch fast.
r = bc("get-property", bus, P, TL, "Tracks")
if r.returncode != 0:
    print("[]"); sys.exit()
paths = json.loads(r.stdout)["data"]
if not paths:
    print("[]"); sys.exit()
cur = ""
rm = bc("get-property", bus, P, PLAYER, "Metadata")
if rm.returncode == 0:
    try:
        cur = unwrap(json.loads(rm.stdout)["data"].get("mpris:trackid", {}), "")
    except Exception:
        cur = ""
try:
    start = paths.index(cur) if cur else 0
except ValueError:
    start = 0
lo = max(0, start - BEFORE) if cur else 0
paths = paths[lo:start + AFTER]
rg = bc("call", bus, P, TL, "GetTracksMetadata", "ao", str(len(paths)), *paths)
if rg.returncode != 0:
    print("[]"); sys.exit()
md = json.loads(rg.stdout)["data"][0]
out = []
before = bool(cur)  # rows before the current track are "played" (greyed out)
for t in md:
    tid = unwrap(t.get("mpris:trackid"), "")
    artist = unwrap(t.get("xesam:artist"), [])
    if isinstance(artist, list):
        artist = ", ".join(artist)
    length = unwrap(t.get("mpris:length"), 0) or 0
    is_cur = tid == cur
    out.append({
        "trackid": tid or "",
        "title": unwrap(t.get("xesam:title"), "") or "",
        "artist": artist or "",
        "length": int(length) // 1000000,
        "art": unwrap(t.get("mpris:artUrl"), "") or "",
        "current": is_cur,
        "played": before and not is_cur,
    })
    if is_cur:
        before = False
print(json.dumps(out))
PY
        ;;
    playlists)
        python3 - "$bus" <<'PY' 2>/dev/null || echo "[]"
import json, subprocess, sys
bus = sys.argv[1]
P = "/org/mpris/MediaPlayer2"
PL = "org.mpris.MediaPlayer2.Playlists"
def bc(*a):
    return subprocess.run(["busctl", "--user", "--json=short", *a],
                          capture_output=True, text=True, timeout=4)
ordering = "Alphabetical"
ro = bc("get-property", bus, P, PL, "Orderings")
if ro.returncode == 0:
    try:
        ords = json.loads(ro.stdout)["data"]
        if ords:
            ordering = ords[0]
    except Exception:
        pass
rg = bc("call", bus, P, PL, "GetPlaylists", "uusb", "0", "200", ordering, "false")
if rg.returncode != 0:
    print("[]"); sys.exit()
lists = json.loads(rg.stdout)["data"][0]
active = ""
ra = bc("get-property", bus, P, PL, "ActivePlaylist")
if ra.returncode == 0:
    try:
        ap = json.loads(ra.stdout)["data"]
        if ap and ap[0]:
            active = ap[1][0]
    except Exception:
        active = ""
out = [{"path": p[0], "name": p[1], "icon": p[2], "active": p[0] == active} for p in lists]
print(json.dumps(out))
PY
        ;;
    goto)
        [ -z "$arg" ] && exit 0
        timeout 4 busctl --user call "$bus" "$P" "$TL" GoTo o "$arg" >/dev/null 2>&1
        ;;
    remove)
        [ -z "$arg" ] && exit 0
        timeout 4 busctl --user call "$bus" "$P" "$TL" RemoveTrack o "$arg" >/dev/null 2>&1
        ;;
    activate)
        [ -z "$arg" ] && exit 0
        timeout 4 busctl --user call "$bus" "$P" "$PL" ActivatePlaylist o "$arg" >/dev/null 2>&1
        ;;
esac
exit 0
