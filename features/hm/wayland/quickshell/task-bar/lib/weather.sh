#!/usr/bin/env bash
# Weather data for the Quickshell hub Calendar/Weather card.
#
# Tries providers in priority order and uses the first that succeeds:
#
#   1. OpenWeatherMap   (only if an owm_api_key is wired)
#   2. PirateWeather    (only if a pirateweather_api_key is wired)
#   3. met.no / Yr      (no key; sends an identifying User-Agent per their ToS)
#   4. Open-Meteo       (no key)
#   5. wttr.in          (no key; last resort)
#
# Reorder/trim the PROVIDERS list below to taste. Each provider normalizes its
# own condition vocabulary (OWM ids, Dark Sky strings, met.no symbol codes, WMO
# codes, WWO codes) onto a small canonical key set that the QML maps to a Nerd
# Font glyph -- so adding/removing a provider never touches the card.
#
# Output is one JSON line, Fahrenheit, fixed to Los Angeles:
#   {"temp":"72","icon":"clear-day","desc":"Clear sky","source":"owm"}
#
# Results are cached 30 min to spare every API; a stale cache is served if all
# providers fail, so the card degrades gracefully offline. ASCII-only by design
# (the glyph table lives in the QML, next to the font).

set -u

# Fixed location: Los Angeles (time.timeZone = America/Los_Angeles).
readonly LAT="34.0522"
readonly LON="-118.2437"

# Priority order; first success wins. Keyed providers self-skip when unkeyed.
readonly PROVIDERS=(owm pirate metno openmeteo wttr)

readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qs-weather"
readonly CACHE_FILE="$CACHE_DIR/weather.json"
readonly CACHE_TTL=1800
mkdir -p "$CACHE_DIR" 2>/dev/null

# --- helpers ------------------------------------------------------------------

round() { awk '{printf "%d", ($1<0?$1-0.5:$1+0.5)}'; }

is_night() {
  local h
  h=$(date +%H)
  [ "$h" -lt 6 ] || [ "$h" -ge 18 ]
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
cap() { printf '%s' "$1" | sed 's/^\(.\)/\U\1/'; }

emit() {
  # temp icon desc source
  printf '{"temp":"%s","icon":"%s","desc":"%s","source":"%s"}\n' \
    "$(json_escape "$1")" "$2" "$(json_escape "$3")" "$4"
}

# Readable description from a canonical key (providers that ship no text use it).
desc_from_key() {
  case "$1" in
  clear-day | clear-night) echo "Clear" ;;
  partly-cloudy-day | partly-cloudy-night) echo "Partly cloudy" ;;
  cloudy) echo "Cloudy" ;;
  fog) echo "Fog" ;;
  drizzle) echo "Drizzle" ;;
  rain) echo "Rain" ;;
  showers) echo "Showers" ;;
  sleet) echo "Sleet" ;;
  snow) echo "Snow" ;;
  thunder) echo "Thunderstorm" ;;
  tornado) echo "Tornado" ;;
  *) echo "Unknown" ;;
  esac
}

# API-key discovery: env var, explicit file, then sops-nix render paths
# (home-manager under $XDG_RUNTIME_DIR/secrets, system under /run/secrets).
#   read_key <ENV_VALUE> <ENV_FILE_PATH> <secret_name>
read_key() {
  local envval="$1" envfile="$2" name="$3" f
  if [ -n "$envval" ]; then
    printf '%s' "$envval"
    return 0
  fi
  for f in \
    "$envfile" \
    "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/secrets/$name" \
    "$HOME/.config/sops-nix/secrets/$name" \
    "/run/secrets/$name"; do
    if [ -n "$f" ] && [ -r "$f" ]; then
      tr -d '[:space:]' <"$f"
      return 0
    fi
  done
  return 1
}
owm_key() { read_key "${OWM_API_KEY:-}" "${OWM_API_KEY_FILE:-}" "owm_api_key"; }
pirate_key() { read_key "${PIRATEWEATHER_API_KEY:-}" "${PIRATEWEATHER_API_KEY_FILE:-}" "pirateweather_api_key"; }

# --- condition -> canonical icon key (one per provider vocabulary) -------------

# OpenWeatherMap condition id. https://openweathermap.org/weather-conditions
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

# PirateWeather / Dark Sky icon string (requested with icon=pirate for the
# extended set). https://docs.pirateweather.net
pirate_icon() {
  case "$1" in
  clear-day) echo "clear-day" ;;
  clear-night) echo "clear-night" ;;
  partly-cloudy-day) echo "partly-cloudy-day" ;;
  partly-cloudy-night) echo "partly-cloudy-night" ;;
  cloudy) echo "cloudy" ;;
  fog) echo "fog" ;;
  wind | breezy | dangerous-wind) echo "cloudy" ;;
  drizzle) echo "drizzle" ;;
  rain) echo "rain" ;;
  sleet | hail) echo "sleet" ;;
  snow | flurries) echo "snow" ;;
  thunderstorm) echo "thunder" ;;
  tornado) echo "tornado" ;;
  *) echo "cloudy" ;;
  esac
}

# met.no symbol_code, e.g. "partlycloudy_night", "lightrainandthunder". The
# _day/_night/_polartwilight suffix carries day/night; the base carries weather.
# https://api.met.no/weatherapi/weathericon/2.0/documentation
metno_icon() {
  local sym="$1" base="$1" night=0
  case "$sym" in
  *_night) base="${sym%_night}" night=1 ;;
  *_day) base="${sym%_day}" ;;
  *_polartwilight) base="${sym%_polartwilight}" ;;
  esac
  case "$base" in
  clearsky) [ "$night" = 1 ] && echo "clear-night" || echo "clear-day" ;;
  fair | partlycloudy) [ "$night" = 1 ] && echo "partly-cloudy-night" || echo "partly-cloudy-day" ;;
  cloudy) echo "cloudy" ;;
  fog) echo "fog" ;;
  *thunder*) echo "thunder" ;;
  *sleet*) echo "sleet" ;;
  *snow*) echo "snow" ;;
  *showers*) echo "showers" ;;
  *drizzle*) echo "drizzle" ;;
  *rain*) echo "rain" ;;
  *) echo "cloudy" ;;
  esac
}

# Open-Meteo WMO weather code. https://open-meteo.com/en/docs
openmeteo_icon() {
  local code="$1" night="$2"
  case "$code" in
  0 | 1) [ "$night" = 1 ] && echo "clear-night" || echo "clear-day" ;;
  2) [ "$night" = 1 ] && echo "partly-cloudy-night" || echo "partly-cloudy-day" ;;
  3) echo "cloudy" ;;
  45 | 48) echo "fog" ;;
  51 | 53 | 55) echo "drizzle" ;;
  56 | 57 | 66 | 67) echo "sleet" ;;
  61 | 63 | 65) echo "rain" ;;
  80 | 81 | 82) echo "showers" ;;
  71 | 73 | 75 | 77 | 85 | 86) echo "snow" ;;
  95 | 96 | 99) echo "thunder" ;;
  *) echo "cloudy" ;;
  esac
}

# wttr.in / WWO weatherCode.
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

# --- providers (each prints one emit line and returns 0 on success) -----------

fetch_owm() {
  local key night id temp desc resp
  key=$(owm_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&units=imperial&appid=${key}") || return 1
  id=$(printf '%s' "$resp" | jq -r '.weather[0].id // empty')
  [ -n "$id" ] || return 1
  temp=$(printf '%s' "$resp" | jq -r '.main.temp // empty' | round)
  desc=$(printf '%s' "$resp" | jq -r '.weather[0].description // "Unknown"')
  if is_night; then night=1; else night=0; fi
  emit "$temp" "$(owm_icon "$id" "$night")" "$(cap "$desc")" "owm"
}

fetch_pirate() {
  local key icon temp summary resp
  key=$(pirate_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.pirateweather.net/forecast/${key}/${LAT},${LON}?units=us&exclude=minutely,hourly,daily,alerts&icon=pirate") || return 1
  icon=$(printf '%s' "$resp" | jq -r '.currently.icon // empty')
  [ -n "$icon" ] || return 1
  temp=$(printf '%s' "$resp" | jq -r '.currently.temperature // empty' | round)
  summary=$(printf '%s' "$resp" | jq -r '.currently.summary // "Unknown"')
  emit "$temp" "$(pirate_icon "$icon")" "$summary" "pirate"
}

fetch_metno() {
  local ua tempc tempf sym key resp
  # met.no ToS requires an identifying User-Agent with a contact; override with
  # $WEATHER_USER_AGENT if you prefer not to ship the default contact.
  ua="${WEATHER_USER_AGENT:-quickshell-weather/1.0 michaelpacheco@protonmail.com}"
  resp=$(curl -sf --max-time 6 -H "User-Agent: $ua" \
    "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${LAT}&lon=${LON}") || return 1
  tempc=$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.air_temperature // empty')
  [ -n "$tempc" ] || return 1
  tempf=$(awk -v c="$tempc" 'BEGIN{f=c*9/5+32; printf "%d", (f<0?f-0.5:f+0.5)}')
  sym=$(printf '%s' "$resp" | jq -r '(.properties.timeseries[0].data.next_1_hours.summary.symbol_code // .properties.timeseries[0].data.next_6_hours.summary.symbol_code) // "cloudy"')
  key=$(metno_icon "$sym")
  emit "$tempf" "$key" "$(desc_from_key "$key")" "metno"
}

fetch_openmeteo() {
  local code isday night temp key resp
  resp=$(curl -sf --max-time 6 \
    "https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current=temperature_2m,weather_code,is_day&temperature_unit=fahrenheit") || return 1
  code=$(printf '%s' "$resp" | jq -r '.current.weather_code // empty')
  [ -n "$code" ] || return 1
  isday=$(printf '%s' "$resp" | jq -r '.current.is_day // 1')
  [ "$isday" = "0" ] && night=1 || night=0
  temp=$(printf '%s' "$resp" | jq -r '.current.temperature_2m // empty' | round)
  key=$(openmeteo_icon "$code" "$night")
  emit "$temp" "$key" "$(desc_from_key "$key")" "openmeteo"
}

fetch_wttr() {
  local night code temp desc resp
  resp=$(curl -sf --max-time 6 "https://wttr.in/${LAT},${LON}?format=j1") || return 1
  code=$(printf '%s' "$resp" | jq -r '.current_condition[0].weatherCode // empty')
  [ -n "$code" ] || return 1
  temp=$(printf '%s' "$resp" | jq -r '.current_condition[0].temp_F // empty')
  [ -n "$temp" ] || return 1
  desc=$(printf '%s' "$resp" | jq -r '.current_condition[0].weatherDesc[0].value // "Unknown"')
  if is_night; then night=1; else night=0; fi
  emit "$temp" "$(wttr_icon "$code" "$night")" "$desc" "wttr"
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

# --- refresh: walk the provider chain, first success wins ---------------------
out=""
for provider in "${PROVIDERS[@]}"; do
  if out=$(fetch_"$provider" 2>/dev/null) && [ -n "$out" ]; then
    break
  fi
  out=""
done

if [ -n "$out" ]; then
  printf '%s\n' "$out" >"$CACHE_FILE"
  printf '%s\n' "$out"
elif [ -f "$CACHE_FILE" ]; then
  cat "$CACHE_FILE" # stale, but better than nothing
else
  emit "--" "cloudy" "Offline" "none"
fi
