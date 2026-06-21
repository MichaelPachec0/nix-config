#!/usr/bin/env bash
# hy3-project -- replicate the ws1 layout (T[H[a,{T[b],T[c]}]]) on the active
# Hyprland workspace; re-run appends another unit as a sibling root tab.
#
# Two kitty shells (a,b) + a browser (c) per unit:
#   one unit  -> T[ H[ a, {T[b],T[c]} ] ]
#   N units   -> { unit1, unit2, ... } as root tabs, one shown at a time
#
# This session runs the Hyprland Lua config, so all dispatch goes through
# `hyprctl eval '<lua>'`. See
# docs/superpowers/plans/2026-06-21-hy3-project-dispatcher-notes.md.
set -euo pipefail

PROG=hy3-project
KCLASS=hy3proj                       # private class on the two kitty panes
WS=""                                # target workspace id (the active one), set in main

# ---- logging --------------------------------------------------------------
# Always-on, appended to a tmpfs file so a bad run can be debugged after the
# fact (by hand or by handing the log to another agent). Override with
# HY3_PROJECT_LOG. Logging never aborts the script (set -e safe).
HY3_PROJECT_LOG="${HY3_PROJECT_LOG:-${XDG_RUNTIME_DIR:-/tmp}/hy3-project.log}"
log() {
  printf '%s [%d] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >>"$HY3_PROJECT_LOG" 2>/dev/null || true
}
# Dump the active workspace's hy3 tree into the log. No-op until the dump_tree
# hy3 patch (overlays/0003) is built; the file simply is not written before then.
log_tree() {
  local f="${XDG_RUNTIME_DIR:-/tmp}/hy3-project-tree.json"
  rm -f "$f" 2>/dev/null || true
  hyprctl eval "hl.plugin.hy3.dump_tree(\"$f\")()" >/dev/null 2>&1 || true
  [ -f "$f" ] && log "tree[$1]: $(cat "$f" 2>/dev/null)" || true
}

usage() {
  cat <<EOF
Usage: $PROG [PATH] [--browser[=CMD]] [--pick]
  PATH            cwd for the two kitty panes (default: \$HOME if missing/not a dir)
  --browser=CMD   window c runs CMD (use --browser=kitty for an all-kitty test)
  --browser       (no value) use \$BROWSER, else xdg default
  (--browser omitted)         use the configured browser
  --pick          choose PATH via a rofi directory picker
EOF
}

# ---- resolution -----------------------------------------------------------

# echo a usable directory: PATH_ARG if it is a dir, else \$HOME (with a notice)
resolve_path() {
  local p="${PATH_ARG:-}" p_real=""
  if [ -n "$p" ]; then
    p="${p/#\~/$HOME}"
    if p_real="$(realpath -e "$p" 2>/dev/null)" && [ -d "$p_real" ]; then
      printf '%s\n' "$p_real"; return 0
    fi
    printf '%s: "%s" is not a directory; using %s\n' "$PROG" "$p" "$HOME" >&2
  fi
  printf '%s\n' "$HOME"
}

# echo the command that launches window c
resolve_browser() {
  if [ "${BROWSER_OVERRIDE+set}" = set ]; then
    if [ -n "$BROWSER_OVERRIDE" ]; then printf '%s\n' "$BROWSER_OVERRIDE"; return 0; fi
    printf '%s\n' "${BROWSER:-xdg-open about:blank}"           # bare --browser
    return 0
  fi
  printf '%s\n' "${HY3_PROJECT_DEFAULT_BROWSER:-firefox} --new-window"
}

# ---- hyprland / hy3 primitives (Lua-config: everything via `hyprctl eval`) -

active_ws() { hyprctl activeworkspace -j | jq -r '.id'; }

# focus a window by address (native dispatcher via the window selector)
focus() { hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"address:$1\" }))" >/dev/null; }

# hy3 dispatchers are closures -- call with a trailing ()
hy3_top()       { hyprctl eval 'hl.plugin.hy3.change_focus("top")()' >/dev/null; }    # select the root node
hy3_lower()     { hyprctl eval 'hl.plugin.hy3.change_focus("lower")()' >/dev/null; }  # descend one level
hy3_maketab()   { hyprctl eval 'hl.plugin.hy3.make_group("tab")()' >/dev/null; }
hy3_groupwith() { hyprctl eval "hl.plugin.hy3.group_with(\"$1\",\"$2\")()" >/dev/null; }  # dir, layout

# launch string for a kitty whose spawned shell starts in $1. kitty's own
# --directory is dropped by Hyprland's exec path, so cd inside an `sh -c`
# wrapper instead; the dir is double-quoted so paths with spaces survive.
kitty_cmd() { printf "sh -c 'cd \"%s\" && exec kitty --class %s'" "$1" "$KCLASS"; }

# spawn_and_wait <label> <launch...> -> echoes the new window address
# Serialized: snapshot addresses, launch silently onto $WS, poll for the one
# new address. Two-stage 5s+5s timeout. [workspace $WS silent] guarantees the
# window lands on the target ws regardless of focus changes during the run.
spawn_and_wait() {
  local label="$1"; shift
  local launch="$*" before after newaddr attempt
  log "spawn[$label]: $launch"
  before="$(hyprctl clients -j | jq -r '.[].address' | sort)"
  hyprctl eval "hl.exec_cmd([=[[workspace $WS silent] $launch]=])" >/dev/null
  for attempt in 1 2; do
    for _ in $(seq 1 50); do                       # 50 * 0.1s = ~5s per attempt
      after="$(hyprctl clients -j | jq -r '.[].address' | sort)"
      newaddr="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n1)"
      [ -n "$newaddr" ] && { log "spawn[$label] -> $newaddr"; printf '%s\n' "$newaddr"; return 0; }
      sleep 0.1
    done
    [ "$attempt" = 1 ] && printf '%s: still waiting for window "%s"...\n' "$PROG" "$label" >&2
  done
  log "spawn[$label] TIMEOUT (~10s)"
  printf '%s: window "%s" never appeared (timeout)\n' "$PROG" "$label" >&2
  return 1
}

# ---- workspace state ------------------------------------------------------

# number of tiled windows on the active ws (floating windows aren't in the tree)
count_tiled() {
  local ws; ws="$(active_ws)"
  hyprctl clients -j | jq --argjson ws "$ws" \
    '[.[] | select(.workspace.id==$ws and .floating==false)] | length'
}

# number of OUR units already on the active ws (2 hy3proj kitties per unit)
count_units() {
  local ws; ws="$(active_ws)"
  hyprctl clients -j | jq --argjson ws "$ws" --arg c "$KCLASS" \
    '[.[] | select(.workspace.id==$ws and .class==$c)] | (length/2) | floor'
}

# address of any tiled window on the active ws (to focus before normalising)
any_tiled() {
  local ws; ws="$(active_ws)"
  hyprctl clients -j | jq -r --argjson ws "$ws" \
    '[.[] | select(.workspace.id==$ws and .floating==false)] | (.[0].address // "")'
}

# address of the left-most VISIBLE tiled window (the active tab's left pane)
left_visible() {
  local ws; ws="$(active_ws)"
  hyprctl clients -j | jq -r --argjson ws "$ws" \
    '[.[] | select(.workspace.id==$ws and .floating==false and .hidden==false)]
     | min_by(.at[0]) | (.address // "")'
}

# ---- build / append -------------------------------------------------------

# build_unit <dir> <browser-cmd> : T[ H[a,{b,c}] ] on an EMPTY active ws
build_unit() {
  local dir="$1" browser="$2" a b
  a="$(spawn_and_wait a "$(kitty_cmd "$dir")")" || exit 1
  focus "$a"
  b="$(spawn_and_wait b "$(kitty_cmd "$dir")")" || exit 1
  focus "$b"
  # shellcheck disable=SC2086  # browser may carry flags, e.g. "firefox --new-window"
  spawn_and_wait c $browser >/dev/null || exit 1   # c need only exist (b's right neighbour)
  focus "$b"; hy3_groupwith r tab          # H[a,{b,c}]
  focus "$a"; hy3_top; hy3_maketab         # wrap into a root tab -> T[H[a,{b,c}]]
}

# normalize_root_tab : wrap whatever loose windows are on the ws into a single
# root tab (R1). Only call this when there is no root tab yet (count_units==0):
# make_group("tab") double-wraps a root that ALREADY has multiple tabs.
normalize_root_tab() {
  local w; w="$(any_tiled)"
  [ -n "$w" ] && focus "$w"
  hy3_top; hy3_maketab
}

# append_unit <dir> <browser-cmd> : add H[a,{b,c}] as a NEW root tab beside the
# existing root tab(s). `top` then `lower` selects a child of the root tab
# (depth-independent), so each spawn lands OUTSIDE the existing tabs as its own
# root tab; then the three are folded into the unit.
append_unit() {
  local dir="$1" browser="$2" w a b
  w="$(left_visible)"
  [ -n "$w" ] && focus "$w"
  hy3_top; hy3_lower                       # select a child of the root tab
  a="$(spawn_and_wait a "$(kitty_cmd "$dir")")" || exit 1   # -> new root tab
  focus "$a"
  b="$(spawn_and_wait b "$(kitty_cmd "$dir")")" || exit 1   # -> new root tab
  focus "$b"
  # shellcheck disable=SC2086
  spawn_and_wait c $browser >/dev/null || exit 1            # c -> new root tab (b's right neighbour)
  focus "$b"; hy3_groupwith r tab          # {b,c}
  focus "$a"; hy3_groupwith r h            # H[a,{b,c}] -> a new root tab
}

# ---- directory picker -----------------------------------------------------

# rofi directory picker rooted at common project parents; echoes the choice
pick_dir() {
  local roots=("$HOME" "$HOME/git" "$HOME/nix-config") r choice
  choice="$(
    for r in "${roots[@]}"; do
      [ -d "$r" ] && find "$r" -mindepth 1 -maxdepth 2 -type d 2>/dev/null
    done | sort -u | rofi -dmenu -i -p "project dir"
  )" || true
  [ -n "$choice" ] && printf '%s\n' "$choice"
  return 0                                  # empty (cancelled) is not an error
}

# ---- main -----------------------------------------------------------------

main() {
  PATH_ARG=""; DO_PICK=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --pick) DO_PICK=1; shift ;;
      --browser=*) BROWSER_OVERRIDE="${1#*=}"; shift ;;
      --browser)   BROWSER_OVERRIDE=""; shift ;;   # bare = default browser (no value consumed)
      -h|--help) usage; exit 0 ;;
      -*) printf '%s: unknown option: %s\n' "$PROG" "$1" >&2; usage >&2; exit 2 ;;
      *) PATH_ARG="$1"; shift ;;
    esac
  done

  if [ "$DO_PICK" = 1 ]; then
    local picked; picked="$(pick_dir)"
    [ -z "$picked" ] && exit 0                       # cancelled
    PATH_ARG="$picked"
  fi

  local dir browser tiled units
  dir="$(resolve_path)"
  browser="$(resolve_browser)"
  WS="$(active_ws)"
  tiled="$(count_tiled)"; units="$(count_units)"
  log "=== run: dir=$dir browser='$browser' ws=$WS tiled=$tiled units=$units pick=$DO_PICK"
  log_tree before

  if [ "$tiled" -eq 0 ]; then
    log "branch: build (empty workspace)"
    build_unit "$dir" "$browser"
  else
    # Loose windows (nothing of ours yet) -> wrap them into their own root tab,
    # then append the new unit as a separate root tab.
    #
    # KNOWN GAP (mixed state): a workspace holding BOTH our units AND loose
    # windows at root is not normalised (units>0 skips it). The planned robust
    # fix reads the exact root structure via the hy3 dump_tree dispatcher
    # (overlays/0003) and builds the unit on a scratch workspace, then moves it
    # in as a root tab -- see the design doc and the dispatcher notes.
    if [ "$units" -eq 0 ]; then
      log "branch: normalize loose windows -> root tab"
      normalize_root_tab
    fi
    log "branch: append unit"
    append_unit "$dir" "$browser"
  fi
  log_tree after
  log "done"
}

main "$@"
