#!/usr/bin/env bash
# Read-only audio/earbud info + Pixel Buds settings + codec switching.
#   btinfo.sh pw    <mac>                 -- PipeWire codec/profile/volume + codec list
#   btinfo.sh codec <mac> <card-profile>  -- switch A2DP codec (pactl set-card-profile)
#   btinfo.sh pbp   <mac>                 -- pbpctrl battery/anc/eq/... (Pixel Buds; cached)
#   btinfo.sh set   <mac> <setting> v...  -- pbpctrl set; invalidates the pbp cache
#
# pbpctrl talks to the buds over an RFCOMM control channel that cannot run
# concurrently and WEDGES if a call is interrupted -- the caller serializes and
# polls slowly. The `timeout` here is a wedge DETECTOR only: a healthy call
# returns in ~2s, so a 15s timeout never interrupts a progressing call; if it
# fires the channel is already stuck, and we un-wedge by reconnecting the device
# (the only reliable userspace reset of an in-use RFCOMM channel; codec/PipeWire
# is unaffected). A cooldown stops reconnect storms.
set -uo pipefail
mode="${1:-}"
mac="${2:-}"
[ -z "$mac" ] && exit 0
und="${mac//:/_}"
cache="${XDG_RUNTIME_DIR:-/tmp}/bt-pbp-${und}"
reco="${XDG_RUNTIME_DIR:-/tmp}/bt-pbp-reco-${und}"

connected() { bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; }

# Un-wedge the control channel by reconnecting (cooldown 30s).
recover() {
    if [ -f "$reco" ]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$reco" 2>/dev/null || echo 0) ))
        [ "$age" -lt 30 ] && return 1
    fi
    date +%s > "$reco"
    bluetoothctl disconnect "$mac" >/dev/null 2>&1
    sleep 3
    bluetoothctl connect "$mac" >/dev/null 2>&1
    sleep 4
    return 0
}

codec_label() {
    case "$1" in
        aac) echo "AAC" ;; ldac) echo "LDAC" ;; aptx) echo "aptX" ;;
        aptx_hd) echo "aptX HD" ;; aptx_ll) echo "aptX LL" ;;
        sbc) echo "SBC" ;; sbc_xq) echo "SBC XQ" ;; opus_05|opus_g) echo "Opus" ;;
        "") echo "" ;; *) echo "$1" | tr '[:lower:]' '[:upper:]' ;;
    esac
}
profile_label() {
    case "$1" in
        a2dp-sink) echo "A2DP" ;; headset-head-unit) echo "HFP/HSP" ;;
        bap-sink) echo "LE Audio" ;; off) echo "Off" ;; "") echo "" ;; *) echo "$1" ;;
    esac
}

if [ "$mode" = "codec" ]; then
    prof="${3:-}"
    [ -z "$prof" ] && exit 0
    pactl set-card-profile "bluez_card.${und}" "$prof" >/dev/null 2>&1
    exit 0
fi

if [ "$mode" = "set" ]; then
    setting="${3:-}"
    [ -z "$setting" ] && exit 0
    shift 3
    connected || exit 0
    if ! timeout 15 pbpctrl -d "$mac" set "$setting" "$@" >/dev/null 2>&1; then
        recover && timeout 15 pbpctrl -d "$mac" set "$setting" "$@" >/dev/null 2>&1
    fi
    rm -f "$cache"
    exit 0
fi

if [ "$mode" = "pw" ]; then
    read -r oid codec profile < <(pw-dump 2>/dev/null | python3 -c "
import json,sys
want='bluez_output.$und'
try: data=json.load(sys.stdin)
except Exception: sys.exit(0)
for o in data:
    p=((o.get('info') or {}).get('props') or {})
    if str(p.get('node.name','')).startswith(want):
        print(o.get('id',''), p.get('api.bluez5.codec',''), p.get('api.bluez5.profile',''))
        break
" 2>/dev/null)
    vol=""
    if [ -n "${oid:-}" ]; then
        v=$(wpctl get-volume "$oid" 2>/dev/null | awk '{print $2}')
        [ -n "$v" ] && vol=$(awk "BEGIN{printf \"%d\", $v*100}")
    fi
    # Available A2DP codecs (as card profiles) + the active profile.
    block=$(pactl list cards 2>/dev/null | awk -v want="bluez_card.${und}" '
        /^[[:space:]]*Name: / { incard = ($2 == want) }
        incard { print }')
    codecs=$(echo "$block" | grep -E "a2dp-sink.*codec.*available: yes" \
        | sed -E 's/^[[:space:]]*([a-z0-9_-]+):.*codec ([^)]+)\).*/\1=\2/' | paste -sd ';')
    active=$(echo "$block" | grep -E "Active Profile:" | awk '{print $3}')
    echo "codec=$(codec_label "${codec:-}")"
    echo "profile=$(profile_label "${profile:-}")"
    echo "volume=${vol}"
    echo "codecs=${codecs}"
    echo "codecprofile=${active}"
    exit 0
fi

if [ "$mode" = "pbp" ]; then
    if [ -f "$cache" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        [ "$age" -lt 20 ] && { cat "$cache"; exit 0; }
    fi
    connected || { [ -f "$cache" ] && cat "$cache"; exit 0; }

    # Canary probe: if it comes back empty while connected, the channel is wedged
    # -> reconnect once, then retry. (15s never fires on a healthy ~2s call.)
    probe() { timeout 15 pbpctrl -d "$mac" get anc 2>/dev/null | head -1; }
    anc=$(probe)
    if [ -z "$anc" ]; then recover && anc=$(probe); fi
    [ -z "$anc" ] && { [ -f "$cache" ] && cat "$cache"; exit 0; } # still wedged

    g() { timeout 15 pbpctrl -d "$mac" "$@" 2>/dev/null; }
    rt=$(g show runtime); sw=$(g show software)
    mp=$(g get multipoint | head -1); ohd=$(g get ohd | head -1)
    veq=$(g get volume-eq | head -1); mono=$(g get mono | head -1)
    speech=$(g get speech-detection | head -1)
    bal=$(g get balance); eq=$(g get eq)

    pct() { echo "$1" | grep -oiE "$2 *bud: *[0-9]+%" | grep -oE '[0-9]+' | head -1; }
    bl=$(pct "$rt" "left"); br=$(pct "$rt" "right")
    bc=$(echo "$rt" | grep -iE "case: *[0-9]+%" | grep -oE '[0-9]+' | head -1)
    fw=$(echo "$sw" | grep -oE 'release_[0-9.]+' | head -1 | sed 's/release_//')
    bL=$(echo "$bal" | grep -oiE "left: *[0-9]+" | grep -oE '[0-9]+' | head -1)
    bR=$(echo "$bal" | grep -oiE "right: *[0-9]+" | grep -oE '[0-9]+' | head -1)
    balv=""
    [ -n "$bL" ] && [ -n "$bR" ] && balv=$(( bR - bL ))
    eqv=$(echo "$eq" | tr -d '[]' | tr ',' '\n' | awk 'NF{printf "%s%d",(NR>1?",":""),($1>=0?$1+0.5:$1-0.5)}')

    out="left=${bl}
right=${br}
case=${bc}
anc=${anc}
multipoint=${mp}
ohd=${ohd}
volumeeq=${veq}
mono=${mono}
speech=${speech}
balance=${balv}
eq=${eqv}
firmware=${fw}"
    if [ -n "${bl}${br}${anc}" ]; then printf '%s\n' "$out" > "$cache.tmp" && mv -f "$cache.tmp" "$cache"; fi
    echo "$out"
    exit 0
fi
exit 0
