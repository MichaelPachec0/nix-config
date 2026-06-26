#!/usr/bin/env bash
# Weather data for the Quickshell hub Calendar/Weather card.
#
# Prefers OpenWeatherMap when an API key is available; otherwise falls back to
# wttr.in (no key required). Location is fixed to Los Angeles (matching the host
# time zone) and temperatures are Fahrenheit. Output is one JSON line:
#
#   {"temp":"72","icon":"clear-day","desc":"Clear sky","source":"owm"}
#
# `icon` is a stable condition key; the QML maps it to a Nerd Font glyph so the
# glyph table lives beside the font, not in this (ASCII-only) script. Results are
# cached for 30 minutes to spare both APIs; a stale cache is served if a refresh
# fails, so the card degrades gracefully offline.

set -u

# Fixed location: Los Angeles (time.timeZone = America/Los_Angeles).
readonly LAT="34.0522"
readonly LON="-118.2437"

readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qs-weather"
readonly CACHE_FILE="$CACHE_DIR/weather.json"
readonly CACHE_TTL=1800
mkdir -p "$CACHE_DIR" 2>/dev/null

# --- OpenWeatherMap API key discovery (sops-nix or explicit override) ---------
# Wire a sops secret named `owm_api_key`: home-manager sops-nix renders it under
# $XDG_RUNTIME_DIR/secrets, system sops-nix under /run/secrets. Or export
# OWM_API_KEY / OWM_API_KEY_FILE. Absent all of these we use wttr.in.
owm_key() {
  if [ -n "${OWM_API_KEY:-}" ]; then
    printf '%s' "$OWM_API_KEY"
    return 0
  fi
  local f
  for f in \
    "${OWM_API_KEY_FILE:-}" \
    "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/secrets/owm_api_key" \
    "$HOME/.config/sops-nix/secrets/owm_api_key" \
    "/run/secrets/owm_api_key"; do
    if [ -n "$f" ] && [ -r "$f" ]; then
      tr -d '[:space:]' <"$f"
      return 0
    fi
  done
  return 1
}

is_night() {
  local h
  h=$(date +%H)
  [ "$h" -lt 6 ] || [ "$h" -ge 18 ]
}

# OpenWeatherMap condition id -> canonical icon key.
# https://openweathermap.org/weather-conditions
owm_icon() {
  local id="$1" night="$2"
  case "$id" in
  800) [ "$night" = 1 ] && echo "clear-night" || echo "clear-day" ;;
  801) [ "$night" = 1 ] && echo "partly-cloudy-night" || echo "partly-cloudy-day" ;;
  802 | 803 | 804) echo "cloudy" ;;
  300 | 301 | 302 | 310 | 311 | 312 | 313 | 314 | 321) echo "drizzle" ;;
  500 | 501 | 502 | 503 | 504) echo "rain" ;;
  511) echo "sleet" ;;
  520 | 521 | 522 | 531) echo "showers" ;;
  200 | 201 | 202 | 210 | 211 | 212 | 221 | 230 | 231 | 232) echo "thunder" ;;
  600 | 601 | 602 | 611 | 612 | 613 | 615 | 616 | 620 | 621 | 622) echo "snow" ;;
  701 | 711 | 721 | 731 | 741 | 751 | 761 | 771) echo "fog" ;;
  781) echo "tornado" ;;
  *) echo "cloudy" ;;
  esac
}

# wttr.in / WWO weatherCode -> canonical icon key.
wttr_icon() {
  local code="$1" night="$2"
  case "$code" in
  113) [ "$night" = 1 ] && echo "clear-night" || echo "clear-day" ;;
  116) [ "$night" = 1 ] && echo "partly-cloudy-night" || echo "partly-cloudy-day" ;;
  119 | 122) echo "cloudy" ;;
  143 | 248 | 260) echo "fog" ;;
  176 | 263 | 266 | 293 | 296 | 353) echo "drizzle" ;;
  299 | 302 | 305 | 308 | 356 | 359) echo "rain" ;;
  179 | 182 | 185 | 281 | 284 | 311 | 314 | 317 | 350 | 362 | 365 | 374 | 377) echo "sleet" ;;
  227 | 230 | 320 | 323 | 326 | 329 | 332 | 335 | 338 | 368 | 371 | 395) echo "snow" ;;
  200 | 386 | 389 | 392) echo "thunder" ;;
  *) echo "cloudy" ;;
  esac
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

cap() {
  printf '%s' "$1" | sed 's/^\(.\)/\U\1/'
}

emit() {
  # temp icon desc source
  printf '{"temp":"%s","icon":"%s","desc":"%s","source":"%s"}\n' \
    "$(json_escape "$1")" "$2" "$(json_escape "$3")" "$4"
}

fetch_owm() {
  local key night id temp desc icon resp
  key=$(owm_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&units=imperial&appid=${key}") || return 1
  [ -n "$resp" ] || return 1
  id=$(printf '%s' "$resp" | jq -r '.weather[0].id // empty')
  [ -n "$id" ] || return 1
  temp=$(printf '%s' "$resp" | jq -r '.main.temp // empty' | awk '{printf "%d", ($1<0?$1-0.5:$1+0.5)}')
  desc=$(printf '%s' "$resp" | jq -r '.weather[0].description // "Unknown"')
  if is_night; then night=1; else night=0; fi
  icon=$(owm_icon "$id" "$night")
  emit "$temp" "$icon" "$(cap "$desc")" "owm"
}

fetch_wttr() {
  local night code temp desc icon resp
  resp=$(curl -sf --max-time 6 "https://wttr.in/${LAT},${LON}?format=j1") || return 1
  [ -n "$resp" ] || return 1
  code=$(printf '%s' "$resp" | jq -r '.current_condition[0].weatherCode // empty')
  [ -n "$code" ] || return 1
  temp=$(printf '%s' "$resp" | jq -r '.current_condition[0].temp_F // empty')
  [ -n "$temp" ] || return 1
  desc=$(printf '%s' "$resp" | jq -r '.current_condition[0].weatherDesc[0].value // "Unknown"')
  if is_night; then night=1; else night=0; fi
  icon=$(wttr_icon "$code" "$night")
  emit "$temp" "$icon" "$desc" "wttr"
}

# --- serve fresh cache --------------------------------------------------------
if [ -f "$CACHE_FILE" ]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  if [ $((now - mtime)) -lt "$CACHE_TTL" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# --- refresh: OpenWeatherMap (if keyed) then wttr.in --------------------------
out=""
if out=$(fetch_owm); then
  :
elif out=$(fetch_wttr); then
  :
else
  out=""
fi

if [ -n "$out" ]; then
  printf '%s\n' "$out" >"$CACHE_FILE"
  printf '%s\n' "$out"
elif [ -f "$CACHE_FILE" ]; then
  cat "$CACHE_FILE" # stale, but better than nothing
else
  emit "--" "cloudy" "Offline" "none"
fi
