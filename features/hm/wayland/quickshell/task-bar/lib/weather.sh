#!/usr/bin/env bash
# Weather data for the Quickshell hub Calendar/Weather card and the bar widget.
#
# Tries providers in priority order and uses the first that succeeds:
#
#   1. OpenWeatherMap   (only if an owm_api_key is wired)
#   2. PirateWeather    (only if a pirateweather_api_key is wired)
#   3. met.no / Yr      (no key; sends an identifying User-Agent per their ToS)
#   4. Open-Meteo       (no key)
#   5. wttr.in          (no key; last resort)
#
# Override the order for testing/pinning with WEATHER_PROVIDERS, e.g.
#   WEATHER_PROVIDERS="openmeteo"  or  WEATHER_PROVIDERS="metno wttr"
#
# Each provider normalizes its own vocabulary/units onto one JSON shape
# (Fahrenheit, mph, fixed to Los Angeles):
#
#   {"temp":"73","icon":"clear-day","desc":"Clear","source":"openmeteo",
#    "feels":"71","humidity":"45","precip":"20","wind":"6","windDir":"NW",
#    "forecast":[{"day":"Fri","icon":"clear-day","hi":"78","lo":"60"}, ...]}
#
# "precip" is the chance of rain (precipitation probability, percent). Empty
# current fields (e.g. met.no has no feels-like and no precip) are "" and the
# QML hides that row. Results are cached 30 min; a stale cache is served if every
# provider fails. ASCII-only (the glyph table lives in the QML, next to the font).

set -u

# Default location (fallback when geolocation is unavailable): Los Angeles.
readonly DEFAULT_LAT="34.0522"
readonly DEFAULT_LON="-118.2437"
LAT="$DEFAULT_LAT" # resolved per-invocation (geo or explicit coords)
LON="$DEFAULT_LON"
PLACE="" # resolved place name (reverse-geocoded for the geo entry)

# Provider priority; first success wins. Keyed providers self-skip when unkeyed.
# Open-Meteo is preferred over met.no among the keyless providers: it supplies
# chance-of-rain (precip) and feels-like globally, which met.no's compact API
# does not (its probability_of_precipitation is null outside the Nordics).
read -ra PROVIDERS <<<"${WEATHER_PROVIDERS:-owm pirate openmeteo metno wttr}"

readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qs-weather"
readonly CACHE_TTL_DEFAULT=1800
CACHE_TTL="${WEATHER_TTL:-$CACHE_TTL_DEFAULT}"

# --- condition thresholds (tunable) ------------------------------------------
COND_HEAT_WARN=85; COND_HEAT_SEVERE=90
COND_COLD_WARN=32; COND_COLD_SEVERE=20   # TUNABLE (user may adjust cold)
COND_WIND_GUST=30
COND_UV_WARN=6; COND_UV_SEVERE=8
COND_FOG_VIS_MI=1
COND_HYDRO_TEMP_MIN=40

readonly GEO_CACHE="$CACHE_DIR/geo.json"
readonly GEO_TTL=1800
# where-am-i: the geoclue demo agent, already whitelisted in geoclue.conf. Found
# at runtime via the nix store so it survives geoclue version bumps. (A proper
# PATH wrapper in the nix config is a planned follow-up.)
WAI="$(ls -1 /nix/store/*-geoclue-*/libexec/geoclue-2.0/demos/where-am-i 2>/dev/null | head -1)"
mkdir -p "$CACHE_DIR" 2>/dev/null

# The fmt_*_tz helpers resolve a city's IANA zone via `TZ=<zone> date`. glibc's
# compiled-in zoneinfo path (/usr/share/zoneinfo) does not exist on NixOS, so an
# unset TZDIR makes a zone silently fall back to UTC (wrong dual times). Point it
# at the stable /etc/zoneinfo symlink, or the tzdata store, when unset.
if [ -z "${TZDIR:-}" ]; then
  if [ -d /etc/zoneinfo ]; then
    export TZDIR=/etc/zoneinfo
  else
    _zd="$(ls -d /nix/store/*-tzdata-*/share/zoneinfo 2>/dev/null | head -1)"
    [ -n "$_zd" ] && export TZDIR="$_zd"
  fi
fi

# --- small helpers ------------------------------------------------------------

round() { awk '{printf "%d", ($1<0?$1-0.5:$1+0.5)}'; }
# round() emits "0" for empty input; round_opt keeps empty empty (for optional
# fields like gust/UV that a provider may not supply -> the popup then hides them).
round_opt() { [ -n "$1" ] && printf '%s' "$1" | round; }
c_to_f() { awk -v c="$1" 'BEGIN{if(c==""){exit}; f=c*9/5+32; printf "%d",(f<0?f-0.5:f+0.5)}'; }
ms_to_mph() { awk -v v="$1" 'BEGIN{if(v==""){exit}; printf "%d", v*2.2369362920544+0.5}'; }

# degrees -> 16-point compass (empty in -> empty out).
deg_compass() {
  awk -v d="$1" 'BEGIN{
    if (d=="") { exit }
    split("N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW", c, " ");
    i=int((d/22.5)+0.5)%16; print c[i+1];
  }'
}

is_night() {
  local h
  h=$(date +%H)
  [ "$h" -lt 6 ] || [ "$h" -ge 18 ]
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
cap() { printf '%s' "$1" | sed 's/^\(.\)/\U\1/'; }
weekday() { date -d "$1" +%a 2>/dev/null || echo "$1"; } # YYYY-MM-DD -> Mon

# A time -> "6:12 AM" (local). Accepts epoch seconds (all-digits), an ISO
# timestamp, or an already-textual clock ("06:12 AM"); empty in -> empty out.
fmt_clock() {
  [ -n "$1" ] || return 0
  case "$1" in
  *[!0-9]*) date -d "$1" +'%-I:%M %p' 2>/dev/null ;;  # ISO / textual
  *) date -d "@$1" +'%-I:%M %p' 2>/dev/null ;;        # epoch seconds
  esac
}

# Canonical icon key -> precipitation type shown beside the chance. Empty for
# non-precip conditions so the popup shows just the percentage (or nothing).
precip_type() {
  case "$1" in
  rain | showers | drizzle | thunder) echo "rain" ;;
  snow) echo "snow" ;;
  sleet) echo "sleet" ;;
  *) echo "" ;;
  esac
}

# Build R_conditions (JSON array of {kind,sev,label}) from the parsed snapshot.
# Integer comparisons guard against empty/non-numeric with 2>/dev/null.
detect_conditions() {
  local items=() t="${R_temp:-}"
  if [ -n "$t" ] && [ "$t" -ge "$COND_HEAT_SEVERE" ] 2>/dev/null; then
    items+=("{\"kind\":\"heat\",\"sev\":\"severe\",\"label\":\"Heat ${t}F\"}")
  elif [ -n "$t" ] && [ "$t" -ge "$COND_HEAT_WARN" ] 2>/dev/null; then
    items+=("{\"kind\":\"heat\",\"sev\":\"warn\",\"label\":\"Heat ${t}F\"}")
  fi
  if [ -n "$t" ] && [ "$t" -le "$COND_COLD_SEVERE" ] 2>/dev/null; then
    items+=("{\"kind\":\"cold\",\"sev\":\"severe\",\"label\":\"Cold ${t}F\"}")
  elif [ -n "$t" ] && [ "$t" -le "$COND_COLD_WARN" ] 2>/dev/null; then
    items+=("{\"kind\":\"cold\",\"sev\":\"warn\",\"label\":\"Cold ${t}F\"}")
  fi
  if [ -n "${R_windGust:-}" ] && [ "$R_windGust" -ge "$COND_WIND_GUST" ] 2>/dev/null; then
    items+=("{\"kind\":\"wind\",\"sev\":\"warn\",\"label\":\"Gusts ${R_windGust} mph\"}")
  fi
  if [ -n "${R_uv:-}" ] && [ "$R_uv" -ge "$COND_UV_SEVERE" ] 2>/dev/null; then
    items+=("{\"kind\":\"uv\",\"sev\":\"severe\",\"label\":\"UV ${R_uv}\"}")
  elif [ -n "${R_uv:-}" ] && [ "$R_uv" -ge "$COND_UV_WARN" ] 2>/dev/null; then
    items+=("{\"kind\":\"uv\",\"sev\":\"warn\",\"label\":\"UV ${R_uv}\"}")
  fi
  if [ -n "${R_visibility:-}" ] && awk "BEGIN{exit !(${R_visibility} <= ${COND_FOG_VIS_MI})}"; then
    items+=("{\"kind\":\"fog\",\"sev\":\"warn\",\"label\":\"Low visibility\"}")
  elif [ "${R_icon:-}" = "fog" ]; then
    items+=("{\"kind\":\"fog\",\"sev\":\"warn\",\"label\":\"Fog\"}")
  fi
  case "${R_icon:-}" in
  snow | sleet) items+=("{\"kind\":\"snow\",\"sev\":\"warn\",\"label\":\"$(cap "${R_icon}")\"}") ;;
  thunder) items+=("{\"kind\":\"thunder\",\"sev\":\"severe\",\"label\":\"Thunderstorm\"}") ;;
  tornado) items+=("{\"kind\":\"thunder\",\"sev\":\"severe\",\"label\":\"Tornado\"}") ;;
  esac
  if [ "$(precip_type "${R_icon:-}")" = "rain" ] || [ "${R_rainSoon:-0}" = "1" ]; then
    items+=("{\"kind\":\"rain\",\"sev\":\"info\",\"label\":\"Rain\"}")
  fi
  if [ "${R_precipHeavy:-0}" = "1" ] && [ -n "$t" ] && [ "$t" -gt "$COND_HYDRO_TEMP_MIN" ] 2>/dev/null; then
    items+=("{\"kind\":\"hydroplaning\",\"sev\":\"warn\",\"label\":\"Hydroplaning risk (est.)\"}")
  fi
  # NWS passthrough: one condition per provider alert.
  local nws
  nws=$(printf '%s' "${R_alerts:-[]}" | jq -c '.[]? | {kind:"nws", sev:"severe", label:.title}' 2>/dev/null)
  local line
  while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done <<<"$nws"
  local IFS=,
  R_conditions="[${items[*]:-}]"
}

# --- timezone-aware clock formatting (for non-current cities) ------------------
# TZNAME holds the target city's IANA zone (empty for the current location).
# NB: TZ="" means UTC in POSIX, so these branch on an empty zone instead of
# blindly exporting TZ.

# A date string -> epoch seconds. A naive (offset-less) time is read in the city
# zone when set (else system); a string with a Z/offset is absolute regardless.
iso_epoch() {
  [ -n "$1" ] || return 0
  if [ -n "$TZNAME" ]; then
    TZ="$TZNAME" date -d "$1" +%s 2>/dev/null
  else
    date -d "$1" +%s 2>/dev/null
  fi
}

# epoch -> "6:12 AM" in the city zone, plus the system-zone time in parens when
# the two differ ("6:12 AM (8:12 AM)"). Empty epoch -> empty. Sunrise/sunset.
fmt_clock_dual() {
  [ -n "$1" ] || return 0
  local sys city
  sys=$(date -d "@$1" +'%-I:%M %p' 2>/dev/null)
  if [ -z "$TZNAME" ]; then
    printf '%s' "$sys"
    return 0
  fi
  city=$(TZ="$TZNAME" date -d "@$1" +'%-I:%M %p' 2>/dev/null)
  if [ "$city" = "$sys" ]; then
    printf '%s' "$city"
  else
    printf '%s (%s)' "$city" "$sys"
  fi
}

# Hour label ("3PM") for an epoch (@...), UTC, or naive-local time, rendered in
# the city zone when set -- keeps the hourly strip on the city's clock.
fmt_hour_tz() {
  [ -n "$1" ] || return 0
  if [ -n "$TZNAME" ]; then
    TZ="$TZNAME" date -d "$1" +'%I%p' 2>/dev/null | sed 's/^0//'
  else
    date -d "$1" +'%I%p' 2>/dev/null | sed 's/^0//'
  fi
}

# A daily forecast row always shows a day glyph (a moon next to a hi/lo reads
# wrong), so fold any night variant to its day counterpart.
day_variant() {
  case "$1" in
  clear-night) echo "clear-day" ;;
  partly-cloudy-night) echo "partly-cloudy-day" ;;
  *) echo "$1" ;;
  esac
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

# Forecast accumulator -> R_fc (a JSON array string).
fc_reset() { R_fc_items=(); }
fc_add() { R_fc_items+=("{\"day\":\"$1\",\"icon\":\"$(day_variant "$2")\",\"hi\":\"$3\",\"lo\":\"$4\"}"); }
fc_build() {
  local IFS=,
  R_fc="[${R_fc_items[*]:-}]"
}

# Hourly accumulator -> R_hr (a JSON array string). Mirrors the daily strip but
# keeps night icon variants (an overnight hour should read as a moon, not a sun).
# Only providers with sub-daily data populate it; emit_rich defaults to [].
hr_reset() { R_hr_items=(); }
hr_add() { R_hr_items+=("{\"h\":\"$1\",\"icon\":\"$2\",\"temp\":\"$3\",\"precip\":\"$4\",\"uv\":\"$5\"}"); }
hr_build() {
  local IFS=,
  R_hr="[${R_hr_items[*]:-}]"
}

# Nowcast accumulator -> R_nowcast (a JSON object string). Reads the
# R_rainSoon/R_nowcastEta/R_nowcastSrc scalars a provider set beforehand; each
# provider runs in its own command-substitution subshell (set -u), so these
# always start unset and are set fresh per fetch_* call.
nowcast_build() {
  local eta="null"
  [ -n "${R_nowcastEta:-}" ] && eta="$R_nowcastEta"
  local soon="false"; [ "${R_rainSoon:-0}" = "1" ] && soon="true"
  local text=""
  if [ "$soon" = "true" ]; then
    if [ "${R_nowcastSrc:-}" = "minutely" ] && [ -n "${R_nowcastEta:-}" ]; then
      text="Rain in ~${R_nowcastEta} min"
    else
      text="Rain likely within the hour"
    fi
  fi
  R_nowcast="{\"rainSoon\":${soon},\"etaMin\":${eta},\"source\":\"${R_nowcastSrc:-none}\",\"text\":\"${text}\"}"
}

# Emit the unified record from R_* globals; arg1 = source. Optional fields
# (uv/windGust/sunrise/sunset/alerts) default empty via :- so a provider that
# can't supply one degrades cleanly; precipType is derived from the icon key.
emit_rich() {
  local ptype nowcast_default='{"rainSoon":false,"etaMin":null,"source":"none","text":""}'
  ptype=$(precip_type "${R_icon}")
  printf '{"temp":"%s","icon":"%s","desc":"%s","source":"%s","feels":"%s","humidity":"%s","precip":"%s","precipType":"%s","uv":"%s","wind":"%s","windGust":"%s","windDir":"%s","visibility":"%s","sunrise":"%s","sunset":"%s","place":"%s","forecast":%s,"hourly":%s,"alerts":%s,"nowcast":%s,"conditions":%s}\n' \
    "$(json_escape "${R_temp}")" "${R_icon}" "$(json_escape "${R_desc}")" "$1" \
    "$(json_escape "${R_feels}")" "$(json_escape "${R_humidity}")" "$(json_escape "${R_precip}")" "${ptype}" \
    "$(json_escape "${R_uv:-}")" \
    "$(json_escape "${R_wind}")" "$(json_escape "${R_windGust:-}")" "$(json_escape "${R_windDir}")" \
    "$(json_escape "${R_visibility:-}")" \
    "$(json_escape "${R_sunrise:-}")" "$(json_escape "${R_sunset:-}")" \
    "$(json_escape "${PLACE}")" "${R_fc:-[]}" "${R_hr:-[]}" "${R_alerts:-[]}" \
    "${R_nowcast:-$nowcast_default}" "${R_conditions:-[]}"
}

# API-key discovery: env var, explicit file, then sops-nix render paths
# (home-manager under $XDG_RUNTIME_DIR/secrets, system under /run/secrets).
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

# --- geolocation (geoclue via the where-am-i agent) ---------------------------

# Reverse-geocode lat/lon to a place name (BigDataCloud, free, no key).
reverse_geocode() {
  local r
  r=$(curl -sf --max-time 5 \
    "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$1&longitude=$2&localityLanguage=en" 2>/dev/null) || return 0
  printf '%s' "$r" | jq -r '.city // .locality // .principalSubdivision // ""' 2>/dev/null
}

# Resolve the live location into LAT/LON/PLACE via geoclue, cached GEO_TTL secs.
# Returns 1 only with no fix and no cache (caller then falls back to defaults).
resolve_geo() {
  local now mtime out lat lon place
  if [ -f "$GEO_CACHE" ]; then
    now=$(date +%s)
    mtime=$(stat -c %Y "$GEO_CACHE" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt "$GEO_TTL" ]; then
      LAT=$(jq -r '.lat // empty' "$GEO_CACHE")
      LON=$(jq -r '.lon // empty' "$GEO_CACHE")
      PLACE=$(jq -r '.place // ""' "$GEO_CACHE")
      [ -n "$LAT" ] && [ -n "$LON" ] && return 0
    fi
  fi
  if [ -n "$WAI" ]; then
    out=$(timeout 18 "$WAI" -t 12 2>/dev/null)
    lat=$(printf '%s' "$out" | awk -F: '/Latitude/{v=$2; gsub(/[^0-9.\-]/,"",v); print v; exit}')
    lon=$(printf '%s' "$out" | awk -F: '/Longitude/{v=$2; gsub(/[^0-9.\-]/,"",v); print v; exit}')
  fi
  if [ -n "${lat:-}" ] && [ -n "${lon:-}" ]; then
    place=$(reverse_geocode "$lat" "$lon")
    LAT="$lat"
    LON="$lon"
    PLACE="$place"
    jq -n --arg lat "$lat" --arg lon "$lon" --arg place "$place" \
      '{lat:$lat,lon:$lon,place:$place}' >"$GEO_CACHE" 2>/dev/null
    return 0
  fi
  if [ -f "$GEO_CACHE" ]; then # a stale fix beats nothing
    LAT=$(jq -r '.lat // empty' "$GEO_CACHE")
    LON=$(jq -r '.lon // empty' "$GEO_CACHE")
    PLACE=$(jq -r '.place // ""' "$GEO_CACHE")
    [ -n "$LAT" ] && [ -n "$LON" ] && return 0
  fi
  return 1
}

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

# PirateWeather / Dark Sky icon string (icon=pirate for the extended set).
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

# met.no symbol_code, e.g. "partlycloudy_night", "lightrainandthunder".
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

# --- providers (each populates R_* and prints one emit_rich line) -------------

fetch_owm() {
  local key night id resp fc_src days i d hi lo fid
  key=$(owm_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&units=imperial&appid=${key}") || return 1
  id=$(printf '%s' "$resp" | jq -r '.weather[0].id // empty')
  [ -n "$id" ] || return 1
  if is_night; then night=1; else night=0; fi
  R_temp=$(printf '%s' "$resp" | jq -r '.main.temp // empty' | round)
  R_icon=$(owm_icon "$id" "$night")
  R_desc=$(cap "$(printf '%s' "$resp" | jq -r '.weather[0].description // "Unknown"')")
  R_feels=$(printf '%s' "$resp" | jq -r '.main.feels_like // empty' | round)
  R_humidity=$(printf '%s' "$resp" | jq -r '.main.humidity // empty')
  R_wind=$(printf '%s' "$resp" | jq -r '.wind.speed // empty' | round)
  R_windDir=$(deg_compass "$(printf '%s' "$resp" | jq -r '.wind.deg // empty')")
  R_visibility=$(awk -v m="$(printf '%s' "$resp" | jq -r '.visibility // empty')" 'BEGIN{if(m=="")exit; printf "%d", m/1609+0.5}')

  # Forecast via the free 5-day/3-hour endpoint, aggregated to daily.
  fc_reset
  fc_src=$(curl -sf --max-time 6 \
    "https://api.openweathermap.org/data/2.5/forecast?lat=${LAT}&lon=${LON}&units=imperial&appid=${key}")
  # Chance of rain: PoP of the nearest 3-hour window (the current endpoint has
  # none). OWM reports pop as 0-1 -> percent.
  R_precip=""
  [ -n "$fc_src" ] && R_precip=$(printf '%s' "$fc_src" | jq -r 'if (.list[0].pop|type)=="number" then (.list[0].pop*100|round) else empty end')
  if [ -n "$fc_src" ]; then
    days=$(printf '%s' "$fc_src" | jq -c '
      [ .list[] | {d:(.dt_txt[0:10]), t:.main.temp, id:.weather[0].id, h:(.dt_txt[11:13])} ]
      | group_by(.d)
      | map({day:.[0].d, hi:(map(.t)|max), lo:(map(.t)|min),
             id:(([.[]|select(.h=="12")|.id][0]) // .[0].id)})
      | .[0:7]' 2>/dev/null)
    if [ -n "$days" ]; then
      for i in 0 1 2 3 4 5 6; do
        d=$(printf '%s' "$days" | jq -r ".[$i].day // empty")
        [ -n "$d" ] || break
        hi=$(printf '%s' "$days" | jq -r ".[$i].hi" | round)
        lo=$(printf '%s' "$days" | jq -r ".[$i].lo" | round)
        fid=$(printf '%s' "$days" | jq -r ".[$i].id")
        fc_add "$(weekday "$d")" "$(owm_icon "$fid" 0)" "$hi" "$lo"
      done
    fi
  fi
  fc_build

  R_windGust=$(round_opt "$(printf '%s' "$resp" | jq -r '.wind.gust // empty')")
  R_sunrise=$(fmt_clock_dual "$(printf '%s' "$resp" | jq -r '.sys.sunrise // empty')")
  R_sunset=$(fmt_clock_dual "$(printf '%s' "$resp" | jq -r '.sys.sunset // empty')")
  # Free /weather has no UV index; left empty.

  # Hourly fallback nowcast: rain likely if the next 1-2 hours cross the PoP bar.
  # owm builds no R_hr (no hourly strip), so this degrades to rainSoon=false.
  R_nowcastSrc=hourly
  if [ -n "${R_hr:-}" ] && printf '%s' "${R_hr:-}" | jq -e '[.[0:2][] | (.precip|tonumber? // 0)] | max >= 50' >/dev/null 2>&1; then
    R_rainSoon=1
  else
    R_rainSoon=0
  fi
  R_nowcastEta=""
  nowcast_build

  detect_conditions
  emit_rich "owm"
}

fetch_pirate() {
  local key resp days i t hi lo fic hours htemp hic hpp hlabel huv
  key=$(pirate_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.pirateweather.net/forecast/${key}/${LAT},${LON}?units=us&exclude=alerts&icon=pirate") || return 1
  [ "$(printf '%s' "$resp" | jq -r '.currently.icon // empty')" != "" ] || return 1
  R_temp=$(printf '%s' "$resp" | jq -r '.currently.temperature // empty' | round)
  R_icon=$(pirate_icon "$(printf '%s' "$resp" | jq -r '.currently.icon')")
  R_desc=$(printf '%s' "$resp" | jq -r '.currently.summary // "Unknown"')
  R_feels=$(printf '%s' "$resp" | jq -r '.currently.apparentTemperature // empty' | round)
  R_humidity=$(printf '%s' "$resp" | jq -r 'if .currently.humidity then (.currently.humidity*100|round) else empty end')
  R_precip=$(printf '%s' "$resp" | jq -r 'if (.currently.precipProbability|type)=="number" then (.currently.precipProbability*100|round) else empty end')
  R_wind=$(printf '%s' "$resp" | jq -r '.currently.windSpeed // empty' | round)
  R_windDir=$(deg_compass "$(printf '%s' "$resp" | jq -r '.currently.windBearing // empty')")
  R_visibility=$(round_opt "$(printf '%s' "$resp" | jq -r '.currently.visibility // empty')")

  fc_reset
  days=$(printf '%s' "$resp" | jq -c '[.daily.data[] | {t:.time, hi:.temperatureHigh, lo:.temperatureLow, ic:.icon}] | .[0:7]' 2>/dev/null)
  if [ -n "$days" ] && [ "$days" != "null" ]; then
    for i in 0 1 2 3 4 5 6; do
      t=$(printf '%s' "$days" | jq -r ".[$i].t // empty")
      [ -n "$t" ] || break
      hi=$(printf '%s' "$days" | jq -r ".[$i].hi" | round)
      lo=$(printf '%s' "$days" | jq -r ".[$i].lo" | round)
      fic=$(pirate_icon "$(printf '%s' "$days" | jq -r ".[$i].ic")")
      fc_add "$(date -d "@$t" +%a 2>/dev/null || echo '?')" "$fic" "$hi" "$lo"
    done
  fi
  fc_build

  # Next 12 hours: label (e.g. 3PM), icon (night variants kept), temp, precip%.
  hr_reset
  hours=$(printf '%s' "$resp" | jq -c '[.hourly.data[] | {t:.time, tp:.temperature, ic:.icon, pp:.precipProbability, uv:.uvIndex}] | .[0:12]' 2>/dev/null)
  if [ -n "$hours" ] && [ "$hours" != "null" ]; then
    for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
      t=$(printf '%s' "$hours" | jq -r ".[$i].t // empty")
      [ -n "$t" ] || break
      htemp=$(printf '%s' "$hours" | jq -r ".[$i].tp // empty" | round)
      hic=$(pirate_icon "$(printf '%s' "$hours" | jq -r ".[$i].ic")")
      hpp=$(printf '%s' "$hours" | jq -r "if (.[$i].pp|type)==\"number\" then (.[$i].pp*100|round) else empty end")
      huv=$(round_opt "$(printf '%s' "$hours" | jq -r ".[$i].uv // empty")")
      hlabel=$(fmt_hour_tz "@$t")
      hr_add "$hlabel" "$hic" "$htemp" "$hpp" "$huv"
    done
  fi
  hr_build

  # Minutely nowcast: first minute in the next hour whose precip prob crosses 50%.
  R_nowcastSrc=minutely
  R_nowcastEta=$(printf '%s' "$resp" | jq -r '
    ([.minutely.data // [] | to_entries[] | select(.value.precipProbability >= 0.5) | .key] | first) // empty')
  if [ -n "$R_nowcastEta" ]; then R_rainSoon=1; else R_rainSoon=0; R_nowcastEta=""; fi
  # Heavy precip now (in/hr) for the hydroplaning heuristic.
  R_precipHeavy=$(printf '%s' "$resp" | jq -r 'if (.currently.precipIntensity // 0) >= 0.3 then "1" else "0" end')
  nowcast_build

  R_uv=$(round_opt "$(printf '%s' "$resp" | jq -r '.currently.uvIndex // empty')")
  R_windGust=$(round_opt "$(printf '%s' "$resp" | jq -r '.currently.windGust // empty')")
  R_sunrise=$(fmt_clock_dual "$(printf '%s' "$resp" | jq -r '.daily.data[0].sunriseTime // empty')")
  R_sunset=$(fmt_clock_dual "$(printf '%s' "$resp" | jq -r '.daily.data[0].sunsetTime // empty')")
  # NWS watches/warnings (Pirate-only). Keep expires as epoch; the popup formats
  # it. `.alerts[]?` tolerates the field being absent when there are none.
  R_alerts=$(printf '%s' "$resp" | jq -c '[.alerts[]? | {title:(.title//""), severity:(.severity//""), expires:(.expires//0)}]' 2>/dev/null)

  detect_conditions
  emit_rich "pirate"
}

fetch_metno() {
  local ua resp sym days n i d hi lo fsym t hours htemp hic hpp hlabel sunresp
  ua="${WEATHER_USER_AGENT:-quickshell-weather/1.0 michaelpacheco@protonmail.com}"
  resp=$(curl -sf --max-time 6 -H "User-Agent: $ua" \
    "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${LAT}&lon=${LON}") || return 1
  [ "$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.air_temperature // empty')" != "" ] || return 1

  R_temp=$(c_to_f "$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.air_temperature')")
  sym=$(printf '%s' "$resp" | jq -r '(.properties.timeseries[0].data.next_1_hours.summary.symbol_code // .properties.timeseries[0].data.next_6_hours.summary.symbol_code) // "cloudy"')
  R_icon=$(metno_icon "$sym")
  R_desc=$(desc_from_key "$R_icon")
  R_feels="" # met.no compact has no apparent temperature
  R_precip="" # met.no probability_of_precipitation is null outside the Nordics
  R_humidity=$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.relative_humidity // empty' | round)
  R_wind=$(ms_to_mph "$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.wind_speed // empty')")
  R_windDir=$(deg_compass "$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.wind_from_direction // empty')")

  # Daily forecast: group the hourly timeseries by date, min/max + midday symbol.
  fc_reset
  days=$(printf '%s' "$resp" | jq -c '
    [ .properties.timeseries[]
      | {d:(.time[0:10]), t:.data.instant.details.air_temperature,
         sym:((.data.next_6_hours.summary.symbol_code // .data.next_1_hours.summary.symbol_code) // "")} ]
    | group_by(.d)
    | map({day:.[0].d, hi:(map(.t)|max), lo:(map(.t)|min),
           sym:([.[]|.sym|select(.!="")] | if length>0 then .[(length/2|floor)] else "cloudy" end)})
    | .[0:7]' 2>/dev/null)
  if [ -n "$days" ]; then
    n=$(printf '%s' "$days" | jq 'length')
    for ((i = 0; i < n && i < 7; i++)); do
      d=$(printf '%s' "$days" | jq -r ".[$i].day")
      hi=$(c_to_f "$(printf '%s' "$days" | jq -r ".[$i].hi")")
      lo=$(c_to_f "$(printf '%s' "$days" | jq -r ".[$i].lo")")
      fsym=$(printf '%s' "$days" | jq -r ".[$i].sym")
      fc_add "$(weekday "$d")" "$(metno_icon "$fsym")" "$hi" "$lo"
    done
  fi
  fc_build

  # Next 12 hourly steps (the timeseries is hourly near-term). Times are UTC, so
  # date converts them to local for the label; temp is C->F; icon from the 1h (or
  # 6h) symbol; precip% only when met.no supplies it (null outside the Nordics,
  # which the strip then hides).
  hr_reset
  hours=$(printf '%s' "$resp" | jq -c '
    [ .properties.timeseries[]
      | {t:.time, tp:.data.instant.details.air_temperature,
         sym:((.data.next_1_hours.summary.symbol_code // .data.next_6_hours.summary.symbol_code) // "cloudy"),
         pp:(.data.next_1_hours.details.probability_of_precipitation // null)} ]
    | .[0:12]' 2>/dev/null)
  if [ -n "$hours" ] && [ "$hours" != "null" ]; then
    for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
      t=$(printf '%s' "$hours" | jq -r ".[$i].t // empty")
      [ -n "$t" ] || break
      htemp=$(c_to_f "$(printf '%s' "$hours" | jq -r ".[$i].tp // empty")")
      hic=$(metno_icon "$(printf '%s' "$hours" | jq -r ".[$i].sym")")
      hpp=$(printf '%s' "$hours" | jq -r "if (.[$i].pp|type)==\"number\" then (.[$i].pp|round) else empty end")
      hlabel=$(fmt_hour_tz "$t")
      hr_add "$hlabel" "$hic" "$htemp" "$hpp" ""
    done
  fi
  hr_build

  R_windGust=$(ms_to_mph "$(printf '%s' "$resp" | jq -r '.properties.timeseries[0].data.instant.details.wind_speed_of_gust // empty')")
  # met.no compact carries no sunrise/sunset or UV; pull sun times from the
  # dedicated Sunrise 3.0 API (one extra call, only when met.no is the active
  # provider). UV is left empty (only the heavier "complete" variant has it).
  sunresp=$(curl -sf --max-time 6 -H "User-Agent: $ua" \
    "https://api.met.no/weatherapi/sunrise/3.0/sun?lat=${LAT}&lon=${LON}&date=$(date +%F)")
  if [ -n "$sunresp" ]; then
    R_sunrise=$(fmt_clock_dual "$(iso_epoch "$(printf '%s' "$sunresp" | jq -r '.properties.sunrise.time // empty')")")
    R_sunset=$(fmt_clock_dual "$(iso_epoch "$(printf '%s' "$sunresp" | jq -r '.properties.sunset.time // empty')")")
  fi

  # Hourly fallback nowcast: rain likely if the next 1-2 hours cross the PoP bar.
  R_nowcastSrc=hourly
  if [ -n "${R_hr:-}" ] && printf '%s' "${R_hr:-}" | jq -e '[.[0:2][] | (.precip|tonumber? // 0)] | max >= 50' >/dev/null 2>&1; then
    R_rainSoon=1
  else
    R_rainSoon=0
  fi
  R_nowcastEta=""
  nowcast_build

  detect_conditions
  emit_rich "metno"
}

fetch_openmeteo() {
  local resp code isday night days i d hi lo fcode t hours hnow htemp hnight hic hpp hlabel huv
  resp=$(curl -sf --max-time 6 \
    "https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,weather_code,is_day,wind_speed_10m,wind_direction_10m,uv_index,wind_gusts_10m,visibility&hourly=temperature_2m,weather_code,precipitation_probability,is_day,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=7") || return 1
  code=$(printf '%s' "$resp" | jq -r '.current.weather_code // empty')
  [ -n "$code" ] || return 1
  isday=$(printf '%s' "$resp" | jq -r '.current.is_day // 1')
  [ "$isday" = "0" ] && night=1 || night=0

  R_temp=$(printf '%s' "$resp" | jq -r '.current.temperature_2m // empty' | round)
  R_icon=$(openmeteo_icon "$code" "$night")
  R_desc=$(desc_from_key "$R_icon")
  R_feels=$(printf '%s' "$resp" | jq -r '.current.apparent_temperature // empty' | round)
  R_humidity=$(printf '%s' "$resp" | jq -r '.current.relative_humidity_2m // empty' | round)
  R_precip=$(printf '%s' "$resp" | jq -r '.current.precipitation_probability // empty') # already percent
  R_wind=$(printf '%s' "$resp" | jq -r '.current.wind_speed_10m // empty' | round)
  R_windDir=$(deg_compass "$(printf '%s' "$resp" | jq -r '.current.wind_direction_10m // empty')")
  R_visibility=$(awk -v m="$(printf '%s' "$resp" | jq -r '.current.visibility // empty')" 'BEGIN{if(m=="")exit; printf "%d", m/1609+0.5}')

  fc_reset
  days=$(printf '%s' "$resp" | jq -c '[.daily.time, .daily.weather_code, .daily.temperature_2m_max, .daily.temperature_2m_min] | transpose | .[0:7]' 2>/dev/null)
  if [ -n "$days" ] && [ "$days" != "null" ]; then
    for i in 0 1 2 3 4 5 6; do
      d=$(printf '%s' "$days" | jq -r ".[$i][0] // empty")
      [ -n "$d" ] || break
      fcode=$(printf '%s' "$days" | jq -r ".[$i][1]")
      hi=$(printf '%s' "$days" | jq -r ".[$i][2]" | round)
      lo=$(printf '%s' "$days" | jq -r ".[$i][3]" | round)
      fc_add "$(weekday "$d")" "$(openmeteo_icon "$fcode" 0)" "$hi" "$lo"
    done
  fi
  fc_build

  # Next 12 hours from the current interval forward. The hourly arrays are
  # parallel, so transpose them into per-hour objects, drop past hours
  # (.t < the current interval), and keep 12. Per-hour is_day picks the icon's
  # day/night variant; precipitation_probability is already a percent.
  hr_reset
  hnow=$(printf '%s' "$resp" | jq -r '.current.time // empty')
  # Floor to the hour so the current hour's slot is kept (.current.time carries
  # minutes; a raw >= would drop it and start the strip at the next hour).
  [ -n "$hnow" ] && hnow="${hnow:0:13}:00"
  hours=$(printf '%s' "$resp" | jq -c --arg now "$hnow" '
    [ [.hourly.time, .hourly.temperature_2m, .hourly.weather_code, .hourly.precipitation_probability, .hourly.is_day, .hourly.uv_index]
      | transpose | .[] | {t:.[0], tp:.[1], wc:.[2], pp:.[3], day:.[4], uv:.[5]} ]
    | map(select(.t >= $now)) | .[0:12]' 2>/dev/null)
  if [ -n "$hours" ] && [ "$hours" != "null" ]; then
    for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
      t=$(printf '%s' "$hours" | jq -r ".[$i].t // empty")
      [ -n "$t" ] || break
      htemp=$(printf '%s' "$hours" | jq -r ".[$i].tp // empty" | round)
      hnight=$(printf '%s' "$hours" | jq -r "if .[$i].day==0 then 1 else 0 end")
      hic=$(openmeteo_icon "$(printf '%s' "$hours" | jq -r ".[$i].wc")" "$hnight")
      hpp=$(printf '%s' "$hours" | jq -r ".[$i].pp // empty")
      huv=$(round_opt "$(printf '%s' "$hours" | jq -r ".[$i].uv // empty")")
      hlabel=$(fmt_hour_tz "$t")
      hr_add "$hlabel" "$hic" "$htemp" "$hpp" "$huv"
    done
  fi
  hr_build

  R_uv=$(round_opt "$(printf '%s' "$resp" | jq -r '.current.uv_index // empty')")
  R_windGust=$(round_opt "$(printf '%s' "$resp" | jq -r '.current.wind_gusts_10m // empty')")
  R_sunrise=$(fmt_clock_dual "$(iso_epoch "$(printf '%s' "$resp" | jq -r '.daily.sunrise[0] // empty')")")
  R_sunset=$(fmt_clock_dual "$(iso_epoch "$(printf '%s' "$resp" | jq -r '.daily.sunset[0] // empty')")")

  # Hourly fallback nowcast: rain likely if the next 1-2 hours cross the PoP bar.
  R_nowcastSrc=hourly
  if [ -n "${R_hr:-}" ] && printf '%s' "${R_hr:-}" | jq -e '[.[0:2][] | (.precip|tonumber? // 0)] | max >= 50' >/dev/null 2>&1; then
    R_rainSoon=1
  else
    R_rainSoon=0
  fi
  R_nowcastEta=""
  nowcast_build

  detect_conditions
  emit_rich "openmeteo"
}

fetch_wttr() {
  local resp night code days i d hi lo fcode
  resp=$(curl -sf --max-time 6 "https://wttr.in/${LAT},${LON}?format=j1") || return 1
  code=$(printf '%s' "$resp" | jq -r '.current_condition[0].weatherCode // empty')
  [ -n "$code" ] || return 1
  if is_night; then night=1; else night=0; fi

  R_temp=$(printf '%s' "$resp" | jq -r '.current_condition[0].temp_F // empty')
  R_icon=$(wttr_icon "$code" "$night")
  R_desc=$(printf '%s' "$resp" | jq -r '.current_condition[0].weatherDesc[0].value // "Unknown"')
  R_feels=$(printf '%s' "$resp" | jq -r '.current_condition[0].FeelsLikeF // empty')
  R_humidity=$(printf '%s' "$resp" | jq -r '.current_condition[0].humidity // empty')
  # Chance of rain: nearest 3-hourly slot (wttr has none on current_condition).
  R_precip=$(printf '%s' "$resp" | jq -r --argjson s "$((10#$(date +%H) / 3))" '.weather[0].hourly[$s].chanceofrain // empty')
  R_wind=$(printf '%s' "$resp" | jq -r '.current_condition[0].windspeedMiles // empty')
  R_windDir=$(printf '%s' "$resp" | jq -r '.current_condition[0].winddir16Point // empty')
  R_visibility=$(round_opt "$(printf '%s' "$resp" | jq -r '.current_condition[0].visibilityMiles // empty')")

  fc_reset
  days=$(printf '%s' "$resp" | jq -c '[.weather[] | {d:.date, hi:.maxtempF, lo:.mintempF, code:(.hourly[4].weatherCode // .hourly[0].weatherCode)}] | .[0:7]' 2>/dev/null)
  if [ -n "$days" ] && [ "$days" != "null" ]; then
    for i in 0 1 2 3 4 5 6; do
      d=$(printf '%s' "$days" | jq -r ".[$i].d // empty")
      [ -n "$d" ] || break
      hi=$(printf '%s' "$days" | jq -r ".[$i].hi")
      lo=$(printf '%s' "$days" | jq -r ".[$i].lo")
      fcode=$(printf '%s' "$days" | jq -r ".[$i].code")
      fc_add "$(weekday "$d")" "$(wttr_icon "$fcode" 0)" "$hi" "$lo"
    done
  fi
  fc_build

  R_uv=$(round_opt "$(printf '%s' "$resp" | jq -r '.current_condition[0].uvIndex // empty')")
  # wttr has no gust on current_condition; take the nearest 3-hourly slot (same
  # index the chance-of-rain uses).
  R_windGust=$(round_opt "$(printf '%s' "$resp" | jq -r --argjson s "$((10#$(date +%H) / 3))" '.weather[0].hourly[$s].WindGustMiles // empty')")
  R_sunrise=$(fmt_clock_dual "$(iso_epoch "$(printf '%s' "$resp" | jq -r 'if .weather[0].astronomy[0].sunrise then (.weather[0].date) + " " + (.weather[0].astronomy[0].sunrise) else empty end')")")
  R_sunset=$(fmt_clock_dual "$(iso_epoch "$(printf '%s' "$resp" | jq -r 'if .weather[0].astronomy[0].sunset then (.weather[0].date) + " " + (.weather[0].astronomy[0].sunset) else empty end')")")

  # Hourly fallback nowcast: rain likely if the next 1-2 hours cross the PoP bar.
  # wttr builds no R_hr (no hourly strip), so this degrades to rainSoon=false.
  R_nowcastSrc=hourly
  if [ -n "${R_hr:-}" ] && printf '%s' "${R_hr:-}" | jq -e '[.[0:2][] | (.precip|tonumber? // 0)] | max >= 50' >/dev/null 2>&1; then
    R_rainSoon=1
  else
    R_rainSoon=0
  fi
  R_nowcastEta=""
  nowcast_build

  detect_conditions
  emit_rich "wttr"
}

# --- resolve target location from args ----------------------------------------
# Usage: weather.sh [<id> [geo | <lat> <lon> [place [tz]]]]
#   weather.sh                       -> geo, cached under id "geo"
#   weather.sh geo                   -> geo, cached under id "geo"
#   weather.sh la 34.0522 -118.2437 "Los Angeles, CA, USA" America/Los_Angeles
LOC_ID="${1:-geo}"
# Target city IANA zone (5th arg; empty for the current location). Read by the
# fmt_*_tz helpers so a non-local city's clock times show in its own zone.
TZNAME="${5:-}"
CACHE_FILE="$CACHE_DIR/weather-${LOC_ID}.json"

# --- serve fresh per-location cache (skips geolocation entirely) --------------
if [ -f "$CACHE_FILE" ]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  if [ $((now - mtime)) -lt "$CACHE_TTL" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# Stale/missing -> resolve coordinates (only now do we touch geoclue).
if [ "${2:-geo}" = "geo" ]; then
  resolve_geo || {
    LAT="$DEFAULT_LAT"
    LON="$DEFAULT_LON"
    PLACE=""
  }
else
  LAT="$2"
  LON="${3:-}"
  PLACE="${4:-}"
  # A lat with no lon (half-specified point) would abort here under `set -u` at
  # the old unguarded LON="$3"; fall back to geo resolution instead of querying
  # a bogus coordinate.
  if [ -z "$LON" ]; then
    resolve_geo || {
      LAT="$DEFAULT_LAT"
      LON="$DEFAULT_LON"
      PLACE=""
    }
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
  # Atomic: write a temp then rename, so a concurrent reader (the bar's FileView)
  # never sees a half-written cache.
  printf '%s\n' "$out" >"$CACHE_FILE.tmp" && mv -f "$CACHE_FILE.tmp" "$CACHE_FILE"
  printf '%s\n' "$out"
elif [ -f "$CACHE_FILE" ]; then
  cat "$CACHE_FILE" # stale, but better than nothing
else
  printf '{"temp":"--","icon":"cloudy","desc":"Offline","source":"none","feels":"","humidity":"","precip":"","precipType":"","uv":"","wind":"","windGust":"","windDir":"","visibility":"","sunrise":"","sunset":"","place":"","forecast":[],"hourly":[],"alerts":[],"nowcast":{"rainSoon":false,"etaMin":null,"source":"none","text":""},"conditions":[]}\n'
fi
