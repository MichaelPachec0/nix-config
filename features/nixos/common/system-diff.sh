# nixos-system-diff [--config-only] [OLD_SYSTEM] NEW_SYSTEM
#
# Expanded "diff to current-system" report, printed by the NixOS activation
# script (and therefore also by `nixos-rebuild dry-activate`, which is the point:
# the report is meant to be read BEFORE committing to a switch).
#
# Everything here is strictly read-only. It reads two system toplevels out of the
# nix store plus /run/booted-system, and writes only its own log files. Nothing
# in here may mutate system state: dry-activate runs it too.
#
# Sections:
#   1  generations, versions, age
#   2  reboot-required verdict (kernel / initrd / modules / systemd)
#   3  package table (nvd), colour-coded per change class
#   4  downgrade callout
#   5  closure size and the biggest per-package size movers
#   6  systemd unit impact (added / removed / restart / reload / no-restart)
#   7  setuid and capability wrapper delta
#   8  /etc delta, minus the unit files already covered by section 6
#   9  users, groups and firewall port delta
#  10  flake input delta
#  11  config diff: real text changes in changed /etc and unit files
#
# --config-only prints sections 1 and 11 alone, for a quick look at what your
# own edits did.
#
# Best effort by design: a broken or missing input for one section must not cost
# you the other nine, so errexit is off and each section is guarded.
set +o errexit

CONFIG_ONLY=0
if [ "${1:-}" = "--config-only" ]; then
  CONFIG_ONLY=1
  shift
fi

case $# in
  1)
    OLD=/run/current-system
    NEW=$1
    ;;
  2)
    OLD=$1
    NEW=$2
    ;;
  *)
    echo "usage: nixos-system-diff [--config-only] [OLD_SYSTEM] NEW_SYSTEM" >&2
    exit 2
    ;;
esac

if [ ! -e "$NEW" ]; then
  echo "nixos-system-diff: no such system: $NEW" >&2
  exit 2
fi

# ---------------------------------------------------------------- presentation

# auto: colour only when stdout is a terminal. The activation wiring forces
# `always`: nixos-rebuild-ng runs switch-to-configuration under
# `systemd-run --pipe`, so stdout there is never a tty. The persisted log always
# gets the escape codes stripped back out.
COLOR_MODE=${NIXOS_DIFF_COLOR:-auto}
use_color=0
case $COLOR_MODE in
  always) use_color=1 ;;
  never) use_color=0 ;;
  *)
    if [ -t 1 ]; then use_color=1; fi
    ;;
esac

if [ "$use_color" = 1 ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_HEAD=$'\033[1;34m'
  C_ADD=$'\033[32m'
  C_DEL=$'\033[31m'
  C_CHG=$'\033[33m'
  C_UP=$'\033[36m'
  C_DOWN=$'\033[1;35m'
  C_WARN=$'\033[1;31m'
  C_DIM=$'\033[2m'
else
  C_RESET=""
  C_BOLD=""
  C_HEAD=""
  C_ADD=""
  C_DEL=""
  C_CHG=""
  C_UP=""
  C_DOWN=""
  C_WARN=""
  C_DIM=""
fi

# How many names any one list prints before it collapses into a count.
LIST_CAP=${NIXOS_DIFF_LIST_CAP:-12}
# Section 11 caps: diff lines per file, and files shown in total.
CONFIG_LINES=${NIXOS_DIFF_CONFIG_LINES:-40}
CONFIG_FILES=${NIXOS_DIFF_CONFIG_FILES:-20}
# Files bigger than this are named but never diffed.
CONFIG_MAX_BYTES=${NIXOS_DIFF_CONFIG_MAX_BYTES:-262144}

hdr() {
  printf '%s\n' "${C_HEAD}== $* ${C_RESET}"
}

note() {
  printf '%s\n' "   ${C_DIM}$*${C_RESET}"
}

# Print a list of names, capped, one indented name per line.
capped_list() {
  local color=$1 prefix=$2 total shown
  shift 2
  total=$#
  if [ "$total" = 0 ]; then return; fi
  shown=0
  printf '%s\n' "   ${color}${prefix} (${total})${C_RESET}"
  for name in "$@"; do
    if [ "$shown" -ge "$LIST_CAP" ]; then
      printf '%s\n' "     ${C_DIM}... and $((total - shown)) more${C_RESET}"
      break
    fi
    printf '%s\n' "     ${color}${name}${C_RESET}"
    shown=$((shown + 1))
  done
}

# ASCII only: nix prints the empty-set symbol for "package did not exist" and a
# rightwards arrow for version transitions.
asciify() {
  sed -e 's/\xe2\x88\x85/(none)/g' -e 's/\xe2\x86\x92/->/g'
}

# Compare two "key<TAB>value" manifests, emitting "added|removed|changed<TAB>key".
#
# One awk pass over both files, NOT a per-line lookup: unit and /etc names carry
# systemd escapes such as etc-NetworkManager-system\x2dconnections.mount, and awk
# expands escape sequences inside a -v assignment, so `-v u="$name"` silently
# turns \x2d into a dash and never matches. Data read from a file is never
# escape-processed, so keying an array on it is safe.
compare_manifests() {
  awk -F'\t' '
    FNR == NR { old[$1] = $2; next }
    {
      seen[$1] = 1
      if (!($1 in old)) print "added\t" $1
      else if (old[$1] != $2) print "changed\t" $1
    }
    END { for (k in old) if (!(k in seen)) print "removed\t" k }
  ' "$1" "$2"
}

WORK=$(mktemp --directory --tmpdir nixos-system-diff.XXXXXXXX)
trap 'rm -rf "$WORK"' EXIT
# Pairs for section 11, one per line: label<TAB>old file<TAB>new file.
: >"$WORK/cfg.pairs"

# ----------------------------------------------- config vs store-hash churn

# Any rebuilt dependency changes every store path that refers to it, so a unit
# or /etc file can move to a new store path with the same text apart from the
# store references. Blank out the hash, and the version part of the store name,
# and what is left is a real config change. Version bumps are already in the
# nvd package table.
#
# The version split follows nix's parseDrvName: the version starts at the first
# dash NOT followed by a letter, so util-linux-2.42.3-bin -> util-linux-VER and
# unit-script-foo-start (no version) is left alone.
STORE_SED='s#/nix/store/[a-z0-9]{32}-#/nix/store/HASH-#g
s#(/nix/store/HASH-[^-/[:space:]"'"'"']+(-[A-Za-z][^-/[:space:]"'"'"']*)*)-[^A-Za-z/[:space:]"'"'"'][^/[:space:]"'"'"']*#\1-VER#g'

# JSON is pretty-printed with sorted keys first: generated JSON such as
# nix/registry.json is one long line, and a one-line diff shows nothing.
norm_store() {
  case $1 in
    *.json)
      if jq -S . "$1" 2>/dev/null | sed -E "$STORE_SED"; then
        return
      fi
      ;;
  esac
  sed -E "$STORE_SED" "$1"
}

# Text file of sane size. An empty file counts as text.
is_text_file() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  [ "$(stat -c %s "$1" 2>/dev/null || echo 0)" -le "$CONFIG_MAX_BYTES" ] || return 1
  [ ! -s "$1" ] || grep -Iq . "$1"
}

# "name<TAB>store path" for each generated unit-script a file refers to.
# ExecStart= etc. point at these, so the logic of a unit lives one hop away and
# a hash-only change in the unit file can hide a real change in its script.
unit_script_refs() {
  grep -oE '/nix/store/[a-z0-9]{32}-unit-script-[^/[:space:]"]+' "$1" 2>/dev/null \
    | sort -u | awk '{ n = $0; sub(/^\/nix\/store\/[a-z0-9]+-/, "", n); print n "\t" $0 }'
}

# config_delta LABEL OLD_FILE NEW_FILE
#   0  real text change (pairs recorded for section 11)
#   1  store-path churn only
#   2  not comparable (binary, directory, too large, unreadable)
config_delta() {
  local label=$1 old=$2 new=$3 rc=1 name old_dir new_dir rel old_name old_path
  # Same final target, e.g. a masked unit whose wrapper path moved but which
  # still resolves to /dev/null on both sides.
  if [ -n "$new" ] && [ "$old" = "$new" ]; then
    return 1
  fi
  if ! is_text_file "$old" || ! is_text_file "$new"; then
    return 2
  fi
  if ! cmp -s <(norm_store "$old") <(norm_store "$new"); then
    printf '%s\t%s\t%s\n' "$label" "$old" "$new" >>"$WORK/cfg.pairs"
    rc=0
  fi
  # One hop into generated unit scripts, paired by name.
  unit_script_refs "$old" >"$WORK/refs.old"
  while IFS=$'\t' read -r name new_dir; do
    # Plain bash compare, not awk -v: script names carry systemd escapes such
    # as \x2d, which awk would expand (see compare_manifests).
    old_dir=""
    while IFS=$'\t' read -r old_name old_path; do
      if [ "$old_name" = "$name" ]; then
        old_dir=$old_path
        break
      fi
    done <"$WORK/refs.old"
    [ -n "$old_dir" ] || continue
    [ "$old_dir" != "$new_dir" ] || continue
    while read -r rel; do
      if is_text_file "$old_dir/$rel" && is_text_file "$new_dir/$rel" \
        && ! cmp -s <(norm_store "$old_dir/$rel") <(norm_store "$new_dir/$rel"); then
        printf '%s\t%s\t%s\n' "$label -> $name/$rel" "$old_dir/$rel" "$new_dir/$rel" >>"$WORK/cfg.pairs"
        rc=0
      fi
    done < <(cd "$new_dir" 2>/dev/null && find . -type f -printf '%P\n' | sort)
  done < <(unit_script_refs "$new")
  return "$rc"
}

# ------------------------------------------------------- 1. generation header

generation_of() {
  local target link
  target=$(readlink -f "$1" 2>/dev/null)
  for link in /nix/var/nix/profiles/system-*-link; do
    if [ "$(readlink -f "$link" 2>/dev/null)" = "$target" ]; then
      basename "$link" | sed -E 's/^system-([0-9]+)-link$/\1/'
      return
    fi
  done
  echo "?"
}

section_header() {
  local old_gen new_gen old_ver new_ver old_age
  old_gen=$(generation_of "$OLD")
  new_gen=$(generation_of "$NEW")
  old_ver=$(cat "$OLD/nixos-version" 2>/dev/null || echo "?")
  new_ver=$(cat "$NEW/nixos-version" 2>/dev/null || echo "?")

  hdr "generations"
  printf '%s\n' "   from  gen ${old_gen}  ${old_ver}"
  printf '%s\n' "     to  gen ${new_gen}  ${new_ver}"
  printf '%s\n' "   ${C_DIM}old  $(readlink -f "$OLD")${C_RESET}"
  printf '%s\n' "   ${C_DIM}new  $(readlink -f "$NEW")${C_RESET}"

  if [ "$old_gen" != "?" ] && [ -e "/nix/var/nix/profiles/system-${old_gen}-link" ]; then
    old_age=$(stat -c %Y "/nix/var/nix/profiles/system-${old_gen}-link" 2>/dev/null)
    if [ -n "${old_age:-}" ]; then
      note "current generation activated $(( ( $(date +%s) - old_age ) / 3600 ))h ago"
    fi
  fi
}

# --------------------------------------------------------- 2. reboot required

section_reboot() {
  local stale=() booted_stale=() component booted_path new_path old_path
  for component in kernel initrd kernel-modules systemd; do
    booted_path=$(readlink -f "/run/booted-system/$component" 2>/dev/null)
    new_path=$(readlink -f "$NEW/$component" 2>/dev/null)
    old_path=$(readlink -f "$OLD/$component" 2>/dev/null)
    if [ -n "$booted_path" ] && [ "$booted_path" != "$new_path" ]; then
      stale+=("$component")
    fi
    if [ -n "$booted_path" ] && [ "$booted_path" != "$old_path" ]; then
      booted_stale+=("$component")
    fi
  done

  hdr "reboot"
  if [ "${#stale[@]}" = 0 ]; then
    printf '%s\n' "   ${C_ADD}no reboot needed: running kernel, initrd, modules and systemd all match${C_RESET}"
    return
  fi

  printf '%s\n' "   ${C_WARN}REBOOT REQUIRED${C_RESET} to run: ${C_WARN}${stale[*]}${C_RESET}"
  if [ "${#booted_stale[@]}" != 0 ]; then
    note "already stale before this switch (${booted_stale[*]}), so a reboot was pending anyway"
  fi
  if [ -e "$NEW/kernel" ] && [ -e /run/booted-system/kernel ]; then
    note "booted $(basename "$(dirname "$(readlink -f /run/booted-system/kernel)")")"
    note "new    $(basename "$(dirname "$(readlink -f "$NEW/kernel")")")"
  fi
}

# --------------------------------------------- 3 + 4. package table, downgrades

section_packages() {
  local table=$WORK/nvd.txt

  # --color never on purpose: nvd colours the version strings but NOT the change
  # class, and its escape codes make the class letter unparseable. Rendering the
  # class ourselves gives one colour per row (add / delete / change / up / down),
  # which is the thing worth seeing at a glance. Cost: nvd's intra-version
  # highlighting is lost.
  if ! nvd --color never --nix-bin-dir="$NIX_BIN_DIR" diff "$OLD" "$NEW" >"$table" 2>"$WORK/nvd.err"; then
    hdr "packages"
    printf '%s\n' "   ${C_WARN}nvd failed${C_RESET}"
    sed -e 's/^/   /' "$WORK/nvd.err"
    return
  fi

  hdr "packages"
  # nvd rows start with [<class><selection>]; class is one of
  # I(nstalled) A(dded) R(emoved) U(pgraded) D(owngraded) C(hanged).
  awk \
    -v c_add="$C_ADD" -v c_del="$C_DEL" -v c_chg="$C_CHG" \
    -v c_up="$C_UP" -v c_down="$C_DOWN" -v c_reset="$C_RESET" \
    -v c_bold="$C_BOLD" '
    /^\[[IARUDC]/ {
      class = substr($0, 2, 1)
      color = ""
      if (class == "A") color = c_add
      else if (class == "R") color = c_del
      else if (class == "U") color = c_up
      else if (class == "D") color = c_down
      else if (class == "C") color = c_chg
      print "   " color $0 c_reset
      next
    }
    /^Closure size:/ { print "   " c_bold $0 c_reset; next }
    { print "   " $0 }
  ' "$table" | asciify

  # 4. downgrades get their own callout: a stale flake input silently rolling a
  # package back is a real failure mode, and one [D.] row in a 400 row table is
  # invisible.
  local down_count
  down_count=$(grep -c '^\[D' "$table" 2>/dev/null)
  down_count=${down_count:-0}
  hdr "downgrades"
  if [ "$down_count" = 0 ]; then
    printf '%s\n' "   ${C_ADD}none${C_RESET}"
  else
    printf '%s\n' "   ${C_DOWN}${down_count} package(s) move BACKWARDS${C_RESET} (stale input, or a deliberate pin)"
    grep '^\[D' "$table" | head -n "$LIST_CAP" | sed -e "s/^/     ${C_DOWN}/" -e "s/\$/${C_RESET}/" | asciify
  fi
}

# ------------------------------------------------------ 5. size, biggest movers

section_size() {
  local closures=$WORK/closures.txt

  hdr "size"
  # nix store diff-closures emits colour even into a pipe; NO_COLOR plus a strip
  # pass keeps the numbers parseable.
  if ! NO_COLOR=1 "$NIX_BIN_DIR/nix" store diff-closures "$OLD" "$NEW" 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;]*m//g' >"$closures"; then
    printf '%s\n' "   ${C_WARN}nix store diff-closures failed${C_RESET}"
    return
  fi

  # Rows look like "zstd: 1.5.6 -> 1.5.7, +12.0 KiB" or "zvbi: -1.0 MiB".
  # Convert the trailing size to bytes so the movers can be ranked.
  awk '
    match($0, /([+-][0-9.]+) (B|KiB|MiB|GiB)$/) {
      tail = substr($0, RSTART, RLENGTH)
      split(tail, parts, " ")
      n = parts[1] + 0
      unit = parts[2]
      mult = 1
      if (unit == "KiB") mult = 1024
      else if (unit == "MiB") mult = 1024 * 1024
      else if (unit == "GiB") mult = 1024 * 1024 * 1024
      printf "%d\t%s\n", n * mult, $0
    }
  ' "$closures" >"$WORK/movers.txt"

  local grew shrank
  grew=$(awk -F'\t' '$1 > 0' "$WORK/movers.txt" | sort -t"$(printf '\t')" -k1,1nr | head -n "$LIST_CAP" | cut -f2-)
  shrank=$(awk -F'\t' '$1 < 0' "$WORK/movers.txt" | sort -t"$(printf '\t')" -k1,1n | head -n "$LIST_CAP" | cut -f2-)

  if [ -n "$grew" ]; then
    printf '%s\n' "   ${C_CHG}largest growth${C_RESET}"
    printf '%s\n' "$grew" | sed -e "s/^/     ${C_CHG}/" -e "s/\$/${C_RESET}/" | asciify
  fi
  if [ -n "$shrank" ]; then
    printf '%s\n' "   ${C_ADD}largest shrink${C_RESET}"
    printf '%s\n' "$shrank" | sed -e "s/^/     ${C_ADD}/" -e "s/\$/${C_RESET}/" | asciify
  fi
  note "$(wc -l <"$closures") package(s) changed size; nvd's Closure size line above has the total"
}

# -------------------------------------------------------- 6. systemd unit impact

# List "<unit> <resolved target>" for every unit file in a toplevel, without
# forking per file (-printf does the symlink read for us).
unit_manifest() {
  local dir=$1/etc/systemd/system
  if [ ! -d "$dir" ]; then return; fi
  (cd "$dir" && find . -maxdepth 1 \( -type l -printf '%f\t%l\n' \) -o \( -type f -printf '%f\tregular-file\n' \) 2>/dev/null) | sort
}

# Best-effort restart prediction, mirroring the X-* directives that
# switch-to-configuration itself honours.
unit_action() {
  local file=$1
  if [ ! -r "$file" ]; then
    echo restart
    return
  fi
  if grep -qs '^X-ReloadIfChanged=true' "$file"; then
    echo reload
  elif grep -qs '^X-RestartIfChanged=false' "$file"; then
    echo norestart
  elif grep -qs '^RefuseManualStop=\(yes\|true\|1\)' "$file"; then
    echo norestart
  elif grep -qs '^X-StopIfChanged=false' "$file"; then
    echo restart-no-stop
  else
    echo restart
  fi
}

section_units() {
  unit_manifest "$OLD" >"$WORK/units.old"
  unit_manifest "$NEW" >"$WORK/units.new"

  hdr "systemd units"
  if [ ! -s "$WORK/units.new" ]; then
    printf '%s\n' "   ${C_WARN}no unit manifest in $NEW${C_RESET}"
    return
  fi

  local added=() removed=() to_restart=() to_reload=() to_norestart=() to_nostop=()
  local status unit action rank shown churn=0

  # Changed units go through a "rank<TAB>action<TAB>unit" file first, so real
  # config changes (rank 0) list ahead of units that only picked up a rebuilt
  # dependency (rank 1) and survive the LIST_CAP cut.
  : >"$WORK/units.changed"
  while IFS=$'\t' read -r status unit; do
    case $status in
      added)
        added+=("$unit")
        ;;
      removed)
        removed+=("$unit")
        ;;
      changed)
        action=$(unit_action "$NEW/etc/systemd/system/$unit")
        config_delta "$unit" \
          "$(readlink -f "$OLD/etc/systemd/system/$unit")" \
          "$(readlink -f "$NEW/etc/systemd/system/$unit")"
        if [ "$?" = 1 ]; then rank=1; else rank=0; fi
        printf '%s\t%s\t%s\n' "$rank" "$action" "$unit" >>"$WORK/units.changed"
        ;;
    esac
  done < <(compare_manifests "$WORK/units.old" "$WORK/units.new")

  while IFS=$'\t' read -r rank action unit; do
    if [ "$rank" = 1 ]; then
      shown="$unit ${C_DIM}(deps only)${C_RESET}"
      churn=$((churn + 1))
    else
      shown=$unit
    fi
    case $action in
      reload) to_reload+=("$shown") ;;
      norestart) to_norestart+=("$shown") ;;
      restart-no-stop) to_nostop+=("$shown") ;;
      *) to_restart+=("$shown") ;;
    esac
  done < <(sort -t"$(printf '\t')" -k1,1n -k3,3 "$WORK/units.changed")

  capped_list "$C_ADD" "new units" ${added+"${added[@]}"}
  capped_list "$C_DEL" "removed units (stopped)" ${removed+"${removed[@]}"}
  capped_list "$C_CHG" "changed, will RESTART" ${to_restart+"${to_restart[@]}"}
  capped_list "$C_UP" "changed, will reload only" ${to_reload+"${to_reload[@]}"}
  capped_list "$C_CHG" "changed, restart without stop first" ${to_nostop+"${to_nostop[@]}"}
  capped_list "$C_DIM" "changed, will NOT restart" ${to_norestart+"${to_norestart[@]}"}

  if [ "${#added[@]}${#removed[@]}${#to_restart[@]}${#to_reload[@]}${#to_nostop[@]}${#to_norestart[@]}" = "000000" ]; then
    printf '%s\n' "   ${C_ADD}no unit changes${C_RESET}"
  fi
  if [ "$churn" != 0 ]; then
    note "(deps only) = $churn unit(s) whose text changed only in store paths: a dependency was rebuilt or bumped"
  fi
  note "prediction from the X-*IfChanged directives; switch-to-configuration has the final say"
}

# ----------------------------------------------------- 7. setuid/caps wrappers

# The wrapper set only exists as the generated start script of
# suid-sgid-wrappers.service, so read the wrapper name plus the mode, caps and
# owner applied to it straight out of that script.
wrapper_manifest() {
  local top=$1 unit script
  unit=$top/etc/systemd/system/suid-sgid-wrappers.service
  if [ ! -r "$unit" ]; then return; fi
  script=$(grep -oE '/nix/store/[a-z0-9]{32}-unit-script-suid-sgid-wrappers-start/bin/[^ ]+' "$unit" | head -1)
  if [ -z "$script" ] || [ ! -r "$script" ]; then return; fi
  awk '
    /^cp .*"\$wrapperDir\// {
      name = $0
      sub(/^.*\$wrapperDir\//, "", name)
      sub(/".*$/, "", name)
      current = name
      next
    }
    current != "" && /^setcap / {
      caps = $2
      gsub(/"/, "", caps)
      info[current] = info[current] " caps=" caps
      next
    }
    current != "" && /^chown / {
      owner = $2
      gsub(/"/, "", owner)
      info[current] = info[current] " owner=" owner
      next
    }
    current != "" && /^chmod .*u\+s/ {
      info[current] = info[current] " setuid"
      next
    }
    current != "" && /^chmod .*g\+s/ {
      info[current] = info[current] " setgid"
      next
    }
    END {
      for (w in info) print w "\t" info[w]
    }
  ' "$script" | sort
}

section_wrappers() {
  wrapper_manifest "$OLD" >"$WORK/wrap.old"
  wrapper_manifest "$NEW" >"$WORK/wrap.new"

  hdr "setuid / capability wrappers"
  if [ ! -s "$WORK/wrap.new" ] && [ ! -s "$WORK/wrap.old" ]; then
    note "no wrapper manifest found in either system"
    return
  fi

  local delta
  delta=$(diff "$WORK/wrap.old" "$WORK/wrap.new" 2>/dev/null)
  if [ -z "$delta" ]; then
    printf '%s\n' "   ${C_ADD}unchanged${C_RESET} ($(wc -l <"$WORK/wrap.new") wrappers)"
    return
  fi

  printf '%s\n' "   ${C_WARN}wrapper set changed - privilege surface, read carefully${C_RESET}"
  printf '%s\n' "$delta" | awk \
    -v c_add="$C_ADD" -v c_del="$C_DEL" -v c_reset="$C_RESET" '
    /^>/ { print "     " c_add "+ " substr($0, 3) c_reset; next }
    /^</ { print "     " c_del "- " substr($0, 3) c_reset; next }
  '
}

# ------------------------------------------------------------- 8. /etc delta

etc_manifest() {
  local dir=$1/etc
  if [ ! -d "$dir" ]; then return; fi
  # No trailing -print: the -printf actions already print, and -print made find
  # emit every entry a second time. The .mode/.uid/.gid siblings are NixOS's own
  # etc metadata, not config, so they are filtered out as noise.
  (cd "$dir" \
    && find . -path ./systemd/system -prune -o \
      \( -type l -printf '%p\t%l\n' \) -o \
      \( -type f -printf '%p\tregular-file\n' \) 2>/dev/null) \
    | sed -e '/^$/d' -e '/\.\(mode\|uid\|gid\)\t/d' | sort
}

section_etc() {
  etc_manifest "$OLD" >"$WORK/etc.old"
  etc_manifest "$NEW" >"$WORK/etc.new"

  hdr "/etc"
  if [ ! -s "$WORK/etc.new" ]; then
    note "no /etc tree in $NEW"
    return
  fi

  local added=() removed=() changed=() opaque=()
  local status path churn=0

  while IFS=$'\t' read -r status path; do
    path=${path#./}
    case $status in
      added) added+=("$path") ;;
      removed) removed+=("$path") ;;
      changed)
        # The flake registry pins every input, so it moves on each lock bump
        # or flake source change. The flake inputs section already reports
        # that in one line per input; diffing it here repeats it in hundreds.
        if [ "$path" = nix/registry.json ]; then
          changed+=("$path (see flake inputs)")
          continue
        fi
        config_delta "etc/$path" \
          "$(readlink -f "$OLD/etc/$path")" \
          "$(readlink -f "$NEW/etc/$path")"
        case $? in
          0) changed+=("$path") ;;
          1) churn=$((churn + 1)) ;;
          *) opaque+=("$path") ;;
        esac
        ;;
    esac
  done < <(compare_manifests "$WORK/etc.old" "$WORK/etc.new")

  capped_list "$C_ADD" "new config files" ${added+"${added[@]}"}
  capped_list "$C_DEL" "removed config files" ${removed+"${removed[@]}"}
  capped_list "$C_CHG" "changed config files (text diff in config diff)" ${changed+"${changed[@]}"}
  capped_list "$C_CHG" "changed, not diffable (binary, directory or large)" ${opaque+"${opaque[@]}"}
  if [ "$churn" != 0 ]; then
    note "$churn more file(s) changed only in store paths (a dependency was rebuilt or bumped)"
  fi
  if [ "${#added[@]}${#removed[@]}${#changed[@]}${#opaque[@]}$churn" = "00000" ]; then
    printf '%s\n' "   ${C_ADD}no /etc changes${C_RESET}"
  fi
  note "unit files excluded here; see the systemd units section"
}

# ------------------------------------------- 9. users, groups, firewall ports

users_json() {
  grep -oE '/nix/store/[a-z0-9]{32}-users-groups.json' "$1/activate" 2>/dev/null | head -1
}

section_users() {
  local old_json new_json
  old_json=$(users_json "$OLD")
  new_json=$(users_json "$NEW")

  hdr "users and groups"
  if [ -z "$new_json" ] || [ ! -r "$new_json" ]; then
    note "no users-groups.json in $NEW"
  else
    if [ -n "$old_json" ] && [ -r "$old_json" ]; then
      jq -r '.users[] | "\(.name)\tuid=\(.uid // "auto") group=\(.group) shell=\(.shell) system=\(.isSystemUser)"' \
        "$old_json" 2>/dev/null | sort >"$WORK/users.old"
      jq -r '.groups[] | "\(.name)\tgid=\(.gid // "auto") members=\((.members // []) | sort | join(","))"' \
        "$old_json" 2>/dev/null | sort >"$WORK/groups.old"
    else
      : >"$WORK/users.old"
      : >"$WORK/groups.old"
    fi
    jq -r '.users[] | "\(.name)\tuid=\(.uid // "auto") group=\(.group) shell=\(.shell) system=\(.isSystemUser)"' \
      "$new_json" 2>/dev/null | sort >"$WORK/users.new"
    jq -r '.groups[] | "\(.name)\tgid=\(.gid // "auto") members=\((.members // []) | sort | join(","))"' \
      "$new_json" 2>/dev/null | sort >"$WORK/groups.new"

    local udelta gdelta
    udelta=$(diff "$WORK/users.old" "$WORK/users.new" 2>/dev/null)
    gdelta=$(diff "$WORK/groups.old" "$WORK/groups.new" 2>/dev/null)
    if [ -z "$udelta" ] && [ -z "$gdelta" ]; then
      printf '%s\n' "   ${C_ADD}unchanged${C_RESET} ($(wc -l <"$WORK/users.new") users, $(wc -l <"$WORK/groups.new") groups)"
    else
      printf '%s\n' "$udelta" "$gdelta" | awk \
        -v c_add="$C_ADD" -v c_del="$C_DEL" -v c_reset="$C_RESET" '
        /^>/ { print "     " c_add "+ " substr($0, 3) c_reset; next }
        /^</ { print "     " c_del "- " substr($0, 3) c_reset; next }
      '
    fi
  fi

  hdr "firewall"
  local old_ports new_ports
  old_ports=$(firewall_ports "$OLD")
  new_ports=$(firewall_ports "$NEW")
  if [ -z "$new_ports" ] && [ -z "$old_ports" ]; then
    note "no iptables firewall-start script found (nftables or firewall disabled)"
    return
  fi
  if [ "$old_ports" = "$new_ports" ]; then
    printf '%s\n' "   ${C_ADD}unchanged${C_RESET}: $(printf '%s' "$new_ports" | tr '\n' ' ')"
    return
  fi
  printf '%s\n' "   ${C_WARN}accepted ports changed${C_RESET}"
  diff <(printf '%s\n' "$old_ports") <(printf '%s\n' "$new_ports") 2>/dev/null | awk \
    -v c_add="$C_ADD" -v c_del="$C_DEL" -v c_reset="$C_RESET" '
    /^>/ { print "     " c_add "+ " substr($0, 3) c_reset; next }
    /^</ { print "     " c_del "- " substr($0, 3) c_reset; next }
  '
}

firewall_ports() {
  local top=$1 unit script
  unit=$top/etc/systemd/system/firewall.service
  if [ ! -r "$unit" ]; then return; fi
  script=$(grep -oE '/nix/store/[a-z0-9]{32}-firewall-start' "$unit" | head -1)
  if [ -z "$script" ] || [ ! -e "$script" ]; then return; fi
  grep -ohE -- '-p (tcp|udp) --dports? [0-9,:]+' "$script"/bin/* 2>/dev/null \
    | sed -E 's/^-p //; s/ --dports? / /' | sort -u
}

# ------------------------------------------------------- 10. flake input delta

lock_manifest() {
  local lock=$1/flake.lock
  if [ ! -r "$lock" ]; then return; fi
  jq -r '
    .nodes | to_entries[]
    | select(.key != "root")
    | select(.value.locked != null)
    | "\(.key)\t\(.value.locked.rev // .value.locked.narHash // "?")\t\(.value.locked.lastModified // 0)"
  ' "$lock" 2>/dev/null | sort
}

section_inputs() {
  hdr "flake inputs"
  lock_manifest "$OLD" >"$WORK/lock.old"
  lock_manifest "$NEW" >"$WORK/lock.new"

  if [ ! -s "$WORK/lock.new" ]; then
    note "no flake.lock recorded in $NEW"
    return
  fi
  if [ ! -s "$WORK/lock.old" ]; then
    note "no flake.lock recorded in $OLD, so nothing to compare (older generation)"
    return
  fi

  local name new_rev new_when old_rev old_when moved=0
  while IFS=$'\t' read -r name new_rev new_when; do
    old_rev=$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$WORK/lock.old")
    old_when=$(awk -F'\t' -v n="$name" '$1 == n { print $3; exit }' "$WORK/lock.old")
    if [ -z "$old_rev" ]; then
      printf '%s\n' "     ${C_ADD}+ ${name} new input at ${new_rev:0:12}${C_RESET}"
      moved=1
      continue
    fi
    if [ "$old_rev" != "$new_rev" ]; then
      printf '%s\n' "     ${C_CHG}~ ${name}${C_RESET} ${old_rev:0:12} -> ${new_rev:0:12}  ${C_DIM}$(date -d "@${old_when:-0}" +%Y-%m-%d 2>/dev/null) -> $(date -d "@${new_when:-0}" +%Y-%m-%d 2>/dev/null)${C_RESET}"
      moved=1
    fi
  done <"$WORK/lock.new"

  while IFS=$'\t' read -r name old_rev old_when; do
    if ! awk -F'\t' -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$WORK/lock.new"; then
      printf '%s\n' "     ${C_DEL}- ${name} input dropped${C_RESET}"
      moved=1
    fi
  done <"$WORK/lock.old"

  if [ "$moved" = 0 ]; then
    printf '%s\n' "   ${C_ADD}no input moved${C_RESET}"
  fi
  note "revs only; this box cannot show upstream commit logs offline"
}

# ------------------------------------------------------------ 11. config diff

# Reads the pairs sections 6 and 8 recorded. Store hashes and versions are
# blanked on both sides, so the diff shows only what changed in the text itself.
section_config() {
  hdr "config diff"
  if [ ! -s "$WORK/cfg.pairs" ]; then
    printf '%s\n' "   ${C_ADD}no config text changed${C_RESET} (other changes are store paths or flake pins only)"
    return
  fi

  local label old new total shown=0
  total=$(wc -l <"$WORK/cfg.pairs")
  while IFS=$'\t' read -r label old new; do
    if [ "$shown" -ge "$CONFIG_FILES" ]; then
      note "... and $((total - shown)) more file(s); raise NIXOS_DIFF_CONFIG_FILES to see them"
      break
    fi
    shown=$((shown + 1))
    printf '%s\n' "   ${C_BOLD}${label}${C_RESET}"
    diff -u --label old --label new <(norm_store "$old") <(norm_store "$new") >"$WORK/cfg.diff"
    # Drop the ---/+++ header; the label line above already names the file.
    # Long lines are cut at 200 columns so a minified file cannot flood the
    # terminal.
    tail -n +3 "$WORK/cfg.diff" | head -n "$CONFIG_LINES" | awk \
      -v c_add="$C_ADD" -v c_del="$C_DEL" -v c_dim="$C_DIM" -v c_reset="$C_RESET" '
      length($0) > 200 { $0 = substr($0, 1, 200) " ..." }
      /^@@/ { print "     " c_dim $0 c_reset; next }
      /^\+/ { print "     " c_add $0 c_reset; next }
      /^-/  { print "     " c_del $0 c_reset; next }
      { print "     " $0 }
    ' | asciify
    local lines
    lines=$(($(wc -l <"$WORK/cfg.diff") - 2))
    if [ "$lines" -gt "$CONFIG_LINES" ]; then
      note "  ... $((lines - CONFIG_LINES)) more diff line(s) cut; raise NIXOS_DIFF_CONFIG_LINES"
    fi
  done <"$WORK/cfg.pairs"
  note "store hashes shown as HASH, versions as VER; added/removed files are listed in their own sections"
}

# ------------------------------------------------------------------- assemble

report() {
  section_header
  if [ "$CONFIG_ONLY" = 1 ]; then
    # Sections 6 and 8 record the pairs section 11 prints; run them silently.
    section_units >/dev/null
    section_etc >/dev/null
    section_config
    return
  fi
  section_reboot
  section_packages
  section_size
  section_units
  section_wrappers
  section_etc
  section_users
  section_inputs
  section_config
}

# The log keeps the plain-text form: colour escapes in a file people grep later
# are just noise. /persist because thanatos runs an ephemeral root, where
# anything written to /etc or /var is gone at the next boot.
log_dir=${NIXOS_DIFF_LOG_DIR:-}
# dry-activate must leave no trace: the activation wiring sets this so a
# pre-flight report never writes a log or touches /etc.
if [ "${NIXOS_DIFF_NO_WRITE:-0}" = 1 ]; then
  log_dir=""
elif [ -z "$log_dir" ]; then
  if [ -d /persist ]; then
    log_dir=/persist/var/log/nixos-diff
  else
    log_dir=/var/log/nixos-diff
  fi
fi

log_file=""
if [ -n "$log_dir" ] && mkdir -p "$log_dir" 2>/dev/null; then
  log_file=$log_dir/$(date +%Y-%m-%dT%H-%M-%S)-$(basename "$(readlink -f "$NEW")" | cut -c1-32).log
fi

if [ -n "$log_file" ]; then
  report | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >"$log_file")
  ln -sfn "$log_file" "$log_dir/latest.log" 2>/dev/null
  # Keep the old single-file changelog path working for anything that reads it.
  cp -f "$log_file" /etc/gradientos-changelog 2>/dev/null
  # Retain a bounded history.
  keep=${NIXOS_DIFF_LOG_KEEP:-20}
  find "$log_dir" -maxdepth 1 -name '*.log' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn | tail -n "+$((keep + 1))" | cut -f2- | while read -r stale; do
    rm -f "$stale"
  done
  printf '%s\n' "   ${C_DIM}report saved to ${log_file}${C_RESET}"
else
  report
fi
