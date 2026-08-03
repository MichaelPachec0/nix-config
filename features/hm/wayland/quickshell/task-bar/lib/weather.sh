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
# World-readable handoff for the resolved country code. $HOME is 0700, so the
# geo cache above is invisible to system services; the e5800 poll service reads
# this instead to pick among a PLMN's per-territory rows. Only the country code
# is published -- coordinates and place name stay in the private cache.
readonly GEO_PUBLIC="${QS_GEO_PUBLIC:-/run/qs-weather/country}"
readonly GEO_TTL=1800
# Last-resume marker, written by the NixOS resume hook
# (powerManagement.resumeCommands in features/nixos/desktop/common). A cache
# entry older than this was produced before the machine last woke, and the
# machine most likely moved while it was asleep.
#
# This is not redundant with the TTLs: a suspend LONGER than 1800s already
# expires them naturally. What it catches is the short hop -- close the lid,
# drive across town, open it 20 minutes later -- where both caches are still
# nominally fresh and both describe the old city.
readonly WAKE_STAMP="${QS_WAKE_STAMP:-/run/qs-wake/stamp}"

# True when $1 was last written before the most recent resume.
#
# No stamp means no resume since boot (/run is a tmpfs), which is NOT a wake --
# answering true there would force a refetch on every single invocation on a
# machine that has never slept.
predates_wake() {
  local wake entry
  [ -f "$WAKE_STAMP" ] || return 1
  [ -f "$1" ] || return 1
  wake=$(stat -c %Y "$WAKE_STAMP" 2>/dev/null || echo 0)
  entry=$(stat -c %Y "$1" 2>/dev/null || echo 0)
  [ "$wake" -gt "$entry" ]
}
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

# jq prelude prepended to every provider query. These replace what used to be
# four shell helpers (round / round_opt / c_to_f / ms_to_mph), each of which
# forked an awk per value:
#
#   r    null -> "", else round half away from zero (jq's round and the old
#        awk `($1<0?$1-0.5:$1+0.5)` agree on every case, .5 and negatives too)
#   cf   Celsius -> Fahrenheit, rounded the same way (met.no is metric)
#   mph  m/s -> mph, truncating v*k+0.5 as the old awk did
#
# An empty value stays empty rather than becoming 0: the popup hides a row whose
# field is "", and a provider that simply does not report gust or UV must not be
# rendered as reporting zero.
#
# Why this shape: each provider ran one `jq` PER FIELD, and the day/hour strips
# ran a handful per row -- Open-Meteo alone spawned 118 processes per refresh.
# Pulling every field in one pass makes the extraction POSITIONAL, so it has to
# be total: each field must emit exactly one line or every read below it shifts
# by one. Hence `// "" | tostring` throughout, never jq's `empty`, which emits
# no line at all.
readonly JQ_DEFS='def r: if . == null then "" else (round|tostring) end; def cf: if . == null then "" else ((. * 9 / 5 + 32)|round|tostring) end; def mph: if . == null then "" else ((. * 2.2369362920544 + 0.5)|floor|tostring) end;'

# Row separator for the multi-field strips. The ASCII unit separator, NOT a tab:
# tab is an IFS *whitespace* character, so bash's `read` collapses runs of them
# and one empty middle field would silently eat the next one.
readonly US=$'\x1f'

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
  # NWS passthrough: one condition per provider alert. `expires` rides along
  # (epoch, 0 when the provider gave none) because it is the ONLY condition
  # kind that carries an end time -- "Heat advisory until 6 PM" is knowable,
  # "Gusts 40 mph" is not. Every other kind below is derived from the current
  # snapshot and expires whenever the next poll says so, so it emits no field.
  local nws
  nws=$(printf '%s' "${R_alerts:-[]}" | jq -c '.[]? | {kind:"nws", sev:"severe", label:.title, expires:(.expires//0)}' 2>/dev/null)
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
  # asOf: when this record was FETCHED, not when it was read. It is written
  # into the cache file, so a cache hit (up to CACHE_TTL old) and a stale-cache
  # fallback (arbitrarily old) both report their true age instead of looking
  # freshly observed. The popup renders the relative time from this.
  printf '{"asOf":%s,"temp":"%s","icon":"%s","desc":"%s","source":"%s","feels":"%s","humidity":"%s","precip":"%s","precipType":"%s","uv":"%s","wind":"%s","windGust":"%s","windDir":"%s","visibility":"%s","sunrise":"%s","sunset":"%s","place":"%s","forecast":%s,"hourly":%s,"alerts":%s,"nowcast":%s,"conditions":%s}\n' \
    "$(date +%s)" \
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

# Reverse-geocode lat/lon to "<place>\t<countryCode>" (BigDataCloud, free, no
# key). The country rides along because the response already carries it and the
# call already happens -- geoclue itself answers with coordinates and no country
# at all, so this request is the only place a country code is available without
# adding a dependency. Either field may be empty; the caller must not invent one.
reverse_geocode() {
  local r
  r=$(curl -sf --max-time 5 \
    "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$1&longitude=$2&localityLanguage=en" 2>/dev/null) || return 0
  printf '%s' "$r" | jq -r '[(.city // .locality // .principalSubdivision // ""), (.countryCode // "")] | @tsv' 2>/dev/null
}

# Publish the country code where a system service can read it. Best-effort and
# never fatal: the directory is created by a tmpfiles rule, and its absence
# simply means consumers get no hint. Written via a temp file + rename so a
# reader never sees a partial value.
publish_country() {
  [ -n "${1:-}" ] || return 0
  local d
  d=$(dirname "$GEO_PUBLIC")
  [ -d "$d" ] || return 0
  printf '%s\n' "$1" >"$GEO_PUBLIC.tmp" 2>/dev/null &&
    mv -f "$GEO_PUBLIC.tmp" "$GEO_PUBLIC" 2>/dev/null || true
}

# Resolve the live location into LAT/LON/PLACE via geoclue, cached GEO_TTL secs.
# Returns 1 only with no fix and no cache (caller then falls back to defaults).
resolve_geo() {
  local now mtime out lat lon place geo country
  if [ -f "$GEO_CACHE" ]; then
    now=$(date +%s)
    mtime=$(stat -c %Y "$GEO_CACHE" 2>/dev/null || echo 0)
    # A fix taken before the last resume is exactly the case this cache must
    # not serve: it is a confident answer to "where am I" from the previous
    # location. The stale-fix fallback further down still keeps it as a last
    # resort if geoclue cannot produce anything better.
    if [ $((now - mtime)) -lt "$GEO_TTL" ] && ! predates_wake "$GEO_CACHE"; then
      LAT=$(jq -r '.lat // empty' "$GEO_CACHE")
      LON=$(jq -r '.lon // empty' "$GEO_CACHE")
      PLACE=$(jq -r '.place // ""' "$GEO_CACHE")
      COUNTRY=$(jq -r '.country // ""' "$GEO_CACHE")
      [ -n "$LAT" ] && [ -n "$LON" ] && return 0
    fi
  fi
  if [ -n "$WAI" ]; then
    out=$(timeout 18 "$WAI" -t 12 2>/dev/null)
    lat=$(printf '%s' "$out" | awk -F: '/Latitude/{v=$2; gsub(/[^0-9.\-]/,"",v); print v; exit}')
    lon=$(printf '%s' "$out" | awk -F: '/Longitude/{v=$2; gsub(/[^0-9.\-]/,"",v); print v; exit}')
  fi
  if [ -n "${lat:-}" ] && [ -n "${lon:-}" ]; then
    geo=$(reverse_geocode "$lat" "$lon")
    place=${geo%%	*}
    country=""
    case "$geo" in *"$(printf '\t')"*) country=${geo##*	} ;; esac
    LAT="$lat"
    LON="$lon"
    PLACE="$place"
    COUNTRY="$country"
    jq -n --arg lat "$lat" --arg lon "$lon" --arg place "$place" --arg country "$country" \
      '{lat:$lat,lon:$lon,place:$place,country:$country}' >"$GEO_CACHE" 2>/dev/null
    publish_country "$country"
    return 0
  fi
  if [ -f "$GEO_CACHE" ]; then # a stale fix beats nothing
    LAT=$(jq -r '.lat // empty' "$GEO_CACHE")
    LON=$(jq -r '.lon // empty' "$GEO_CACHE")
    PLACE=$(jq -r '.place // ""' "$GEO_CACHE")
    COUNTRY=$(jq -r '.country // ""' "$GEO_CACHE")
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
  local key night resp fc_src f d hi lo fid
  key=$(owm_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&units=imperial&appid=${key}") || return 1
  if is_night; then night=1; else night=0; fi

  # One pass for every scalar; field ORDER is the contract with the reads below.
  mapfile -t f < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    (.weather[0].id // "" | tostring), (.main.temp|r),
    (.weather[0].description // "Unknown"), (.main.feels_like|r),
    (.main.humidity // "" | tostring), (.wind.speed|r), (.wind.deg // "" | tostring),
    (if .visibility == null then "" else ((.visibility / 1609 + 0.5)|floor|tostring) end),
    (.wind.gust|r), (.sys.sunrise // "" | tostring), (.sys.sunset // "" | tostring)')
  [ -n "${f[0]:-}" ] || return 1

  R_icon=$(owm_icon "${f[0]}" "$night")
  R_temp="${f[1]:-}"
  R_desc=$(cap "${f[2]:-}")
  R_feels="${f[3]:-}"
  R_humidity="${f[4]:-}"
  R_wind="${f[5]:-}"
  R_windDir=$(deg_compass "${f[6]:-}")
  R_visibility="${f[7]:-}"
  R_windGust="${f[8]:-}"
  R_sunrise=$(fmt_clock_dual "${f[9]:-}")
  R_sunset=$(fmt_clock_dual "${f[10]:-}")
  # Free /weather has no UV index; left empty.

  # Forecast via the free 5-day/3-hour endpoint, aggregated to daily.
  fc_reset
  fc_src=$(curl -sf --max-time 6 \
    "https://api.openweathermap.org/data/2.5/forecast?lat=${LAT}&lon=${LON}&units=imperial&appid=${key}")
  # Chance of rain: PoP of the nearest 3-hour window (the current endpoint has
  # none). OWM reports pop as 0-1 -> percent.
  R_precip=""
  if [ -n "$fc_src" ]; then
    R_precip=$(printf '%s' "$fc_src" | jq -r 'if (.list[0].pop|type) == "number" then (.list[0].pop*100|round|tostring) else "" end')
    while IFS="$US" read -r d hi lo fid; do
      [ -n "$d" ] || continue
      fc_add "$(weekday "$d")" "$(owm_icon "$fid" 0)" "$hi" "$lo"
    done < <(printf '%s' "$fc_src" | jq -r "$JQ_DEFS"'
      [ .list[] | {d:(.dt_txt[0:10]), t:.main.temp, id:.weather[0].id, h:(.dt_txt[11:13])} ]
      | group_by(.d)
      | map({day:.[0].d, hi:(map(.t)|max), lo:(map(.t)|min),
             id:(([.[]|select(.h=="12")|.id][0]) // .[0].id)})
      | .[0:7][]
      | [.day, (.hi|r), (.lo|r), (.id // "" | tostring)] | join("\u001f")' 2>/dev/null)
  fi
  fc_build

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
  local key resp f t hi lo fic htemp hic hpp hlabel huv
  key=$(pirate_key) || return 1
  [ -n "$key" ] || return 1
  resp=$(curl -sf --max-time 6 \
    "https://api.pirateweather.net/forecast/${key}/${LAT},${LON}?units=us&exclude=alerts&icon=pirate") || return 1

  # One pass for every scalar; field ORDER is the contract with the reads below.
  # humidity and precipProbability arrive as 0-1 fractions, so they scale here.
  mapfile -t f < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    (.currently.icon // ""), (.currently.temperature|r), (.currently.summary // "Unknown"),
    (.currently.apparentTemperature|r),
    (if .currently.humidity then (.currently.humidity*100|round|tostring) else "" end),
    (if (.currently.precipProbability|type) == "number" then (.currently.precipProbability*100|round|tostring) else "" end),
    (.currently.windSpeed|r), (.currently.windBearing // "" | tostring),
    (.currently.visibility|r), (.currently.uvIndex|r), (.currently.windGust|r),
    (if (.currently.precipIntensity // 0) >= 0.3 then "1" else "0" end),
    (.daily.data[0].sunriseTime // "" | tostring), (.daily.data[0].sunsetTime // "" | tostring),
    (([.minutely.data // [] | to_entries[] | select(.value.precipProbability >= 0.5) | .key] | first) // "" | tostring)')
  [ -n "${f[0]:-}" ] || return 1
  R_icon=$(pirate_icon "${f[0]}")
  R_temp="${f[1]:-}"
  R_desc="${f[2]:-}"
  R_feels="${f[3]:-}"
  R_humidity="${f[4]:-}"
  R_precip="${f[5]:-}"
  R_wind="${f[6]:-}"
  R_windDir=$(deg_compass "${f[7]:-}")
  R_visibility="${f[8]:-}"
  R_uv="${f[9]:-}"
  R_windGust="${f[10]:-}"
  R_precipHeavy="${f[11]:-0}"
  R_sunrise=$(fmt_clock_dual "${f[12]:-}")
  R_sunset=$(fmt_clock_dual "${f[13]:-}")

  fc_reset
  while IFS="$US" read -r t hi lo fic; do
    [ -n "$t" ] || continue
    fc_add "$(date -d "@$t" +%a 2>/dev/null || echo '?')" "$(pirate_icon "$fic")" "$hi" "$lo"
  done < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    .daily.data[0:7][]
    | [(.time // "" | tostring), (.temperatureHigh|r), (.temperatureLow|r), (.icon // "")]
    | join("\u001f")' 2>/dev/null)
  fc_build

  # Next 12 hours: label (e.g. 3PM), icon (night variants kept), temp, precip%.
  hr_reset
  while IFS="$US" read -r t htemp hic hpp huv; do
    [ -n "$t" ] || continue
    hlabel=$(fmt_hour_tz "@$t")
    hr_add "$hlabel" "$(pirate_icon "$hic")" "$htemp" "$hpp" "$huv"
  done < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    .hourly.data[0:12][]
    | [(.time // "" | tostring), (.temperature|r), (.icon // ""),
       (if (.precipProbability|type) == "number" then (.precipProbability*100|round|tostring) else "" end),
       (.uvIndex|r)]
    | join("\u001f")' 2>/dev/null)
  hr_build

  # Minutely nowcast: first minute in the next hour whose precip prob crosses 50%.
  R_nowcastSrc=minutely
  R_nowcastEta="${f[14]:-}"
  if [ -n "$R_nowcastEta" ]; then R_rainSoon=1; else R_rainSoon=0; R_nowcastEta=""; fi
  nowcast_build
  # NWS watches/warnings (Pirate-only). Keep expires as epoch; the popup formats
  # it. `.alerts[]?` tolerates the field being absent when there are none.
  R_alerts=$(printf '%s' "$resp" | jq -c '[.alerts[]? | {title:(.title//""), severity:(.severity//""), expires:(.expires//0)}]' 2>/dev/null)

  detect_conditions
  emit_rich "pirate"
}

fetch_metno() {
  local ua resp f d hi lo fsym t htemp hpp hlabel sunresp
  ua="${WEATHER_USER_AGENT:-quickshell-weather/1.0 michaelpacheco@protonmail.com}"
  resp=$(curl -sf --max-time 6 -H "User-Agent: $ua" \
    "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${LAT}&lon=${LON}") || return 1

  # One pass for every scalar; field ORDER is the contract with the reads below.
  # met.no is metric, so C->F and m/s->mph happen in jq (cf / mph).
  mapfile -t f < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    .properties.timeseries[0].data as $d
    | ($d.instant.details.air_temperature // "" | tostring),
      ($d.instant.details.air_temperature|cf),
      (($d.next_1_hours.summary.symbol_code // $d.next_6_hours.summary.symbol_code) // "cloudy"),
      ($d.instant.details.relative_humidity|r),
      ($d.instant.details.wind_speed|mph),
      ($d.instant.details.wind_from_direction // "" | tostring),
      ($d.instant.details.wind_speed_of_gust|mph)')
  [ -n "${f[0]:-}" ] || return 1

  R_temp="${f[1]:-}"
  R_icon=$(metno_icon "${f[2]:-cloudy}")
  R_desc=$(desc_from_key "$R_icon")
  R_feels="" # met.no compact has no apparent temperature
  R_precip="" # met.no probability_of_precipitation is null outside the Nordics
  R_humidity="${f[3]:-}"
  R_wind="${f[4]:-}"
  R_windDir=$(deg_compass "${f[5]:-}")
  R_windGust="${f[6]:-}"

  # Daily forecast: group the hourly timeseries by date, min/max + midday symbol.
  fc_reset
  while IFS="$US" read -r d hi lo fsym; do
    [ -n "$d" ] || continue
    fc_add "$(weekday "$d")" "$(metno_icon "$fsym")" "$hi" "$lo"
  done < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    [ .properties.timeseries[]
      | {d:(.time[0:10]), t:.data.instant.details.air_temperature,
         sym:((.data.next_6_hours.summary.symbol_code // .data.next_1_hours.summary.symbol_code) // "")} ]
    | group_by(.d)
    | map({day:.[0].d, hi:(map(.t)|max), lo:(map(.t)|min),
           sym:([.[]|.sym|select(.!="")] | if length>0 then .[(length/2|floor)] else "cloudy" end)})
    | .[0:7][]
    | [.day, (.hi|cf), (.lo|cf), .sym] | join("\u001f")' 2>/dev/null)
  fc_build

  # Next 12 hourly steps (the timeseries is hourly near-term). Times are UTC, so
  # date converts them to local for the label; temp is C->F; icon from the 1h (or
  # 6h) symbol; precip% only when met.no supplies it (null outside the Nordics,
  # which the strip then hides).
  hr_reset
  while IFS="$US" read -r t htemp fsym hpp; do
    [ -n "$t" ] || continue
    hlabel=$(fmt_hour_tz "$t")
    hr_add "$hlabel" "$(metno_icon "$fsym")" "$htemp" "$hpp" ""
  done < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    .properties.timeseries[0:12][]
    | [ .time, (.data.instant.details.air_temperature|cf),
        ((.data.next_1_hours.summary.symbol_code // .data.next_6_hours.summary.symbol_code) // "cloudy"),
        (.data.next_1_hours.details.probability_of_precipitation
         | if type == "number" then (round|tostring) else "" end) ]
    | join("\u001f")' 2>/dev/null)
  hr_build

  # met.no compact carries no sunrise/sunset or UV; pull sun times from the
  # dedicated Sunrise 3.0 API (one extra call, only when met.no is the active
  # provider). UV is left empty (only the heavier "complete" variant has it).
  sunresp=$(curl -sf --max-time 6 -H "User-Agent: $ua" \
    "https://api.met.no/weatherapi/sunrise/3.0/sun?lat=${LAT}&lon=${LON}&date=$(date +%F)")
  if [ -n "$sunresp" ]; then
    mapfile -t f < <(printf '%s' "$sunresp" | jq -r '.properties.sunrise.time // "", .properties.sunset.time // ""')
    R_sunrise=$(fmt_clock_dual "$(iso_epoch "${f[0]:-}")")
    R_sunset=$(fmt_clock_dual "$(iso_epoch "${f[1]:-}")")
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
  local resp night f d hi lo fcode t hnight hic hpp hlabel huv htemp
  resp=$(curl -sf --max-time 6 \
    "https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,weather_code,is_day,wind_speed_10m,wind_direction_10m,uv_index,wind_gusts_10m,visibility&hourly=temperature_2m,weather_code,precipitation_probability,is_day,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=7") || return 1

  # One pass for every scalar. Field ORDER here is the contract with the reads
  # below -- keep them together.
  mapfile -t f < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    .current
    | (.weather_code // "" | tostring), (.is_day // 1 | tostring), (.temperature_2m|r),
      (.apparent_temperature|r), (.relative_humidity_2m|r),
      (.precipitation_probability // "" | tostring), (.wind_speed_10m|r),
      (.wind_direction_10m // "" | tostring),
      (if .visibility == null then "" else ((.visibility / 1609 + 0.5)|floor|tostring) end),
      (.uv_index|r), (.wind_gusts_10m|r), (.time // "")')
  [ -n "${f[0]:-}" ] || return 1
  [ "${f[1]:-1}" = "0" ] && night=1 || night=0

  R_temp="${f[2]:-}"
  R_icon=$(openmeteo_icon "${f[0]}" "$night")
  R_desc=$(desc_from_key "$R_icon")
  R_feels="${f[3]:-}"
  R_humidity="${f[4]:-}"
  R_precip="${f[5]:-}" # already percent
  R_wind="${f[6]:-}"
  R_windDir=$(deg_compass "${f[7]:-}")
  R_visibility="${f[8]:-}"
  R_uv="${f[9]:-}"
  R_windGust="${f[10]:-}"

  # One pass for the 7-day strip: the daily arrays are parallel, so transpose
  # them and emit one tab-separated row per day.
  fc_reset
  while IFS="$US" read -r d fcode hi lo; do
    [ -n "$d" ] || continue
    fc_add "$(weekday "$d")" "$(openmeteo_icon "$fcode" 0)" "$hi" "$lo"
  done < <(printf '%s' "$resp" | jq -r "$JQ_DEFS"'
    [.daily.time, .daily.weather_code, .daily.temperature_2m_max, .daily.temperature_2m_min]
    | transpose | .[0:7] | .[]
    | [(.[0] // ""), (.[1] // "" | tostring), (.[2]|r), (.[3]|r)] | join("\u001f")' 2>/dev/null)
  fc_build

  # Next 12 hours from the current interval forward. Same transpose, then drop
  # past hours (.t < the current interval) and keep 12. Per-hour is_day picks
  # the icon's day/night variant; precipitation_probability is already percent.
  #
  # Floor $now to the hour so the CURRENT hour's slot survives the filter:
  # .current.time carries minutes, and a raw >= would drop it and start the
  # strip an hour late.
  hr_reset
  while IFS="$US" read -r t htemp hnight fcode hpp huv; do
    [ -n "$t" ] || continue
    hic=$(openmeteo_icon "$fcode" "$hnight")
    hlabel=$(fmt_hour_tz "$t")
    hr_add "$hlabel" "$hic" "$htemp" "$hpp" "$huv"
  done < <(printf '%s' "$resp" | jq -r --arg now "${f[11]:0:13}${f[11]:+:00}" "$JQ_DEFS"'
    [ [.hourly.time, .hourly.temperature_2m, .hourly.weather_code, .hourly.precipitation_probability, .hourly.is_day, .hourly.uv_index]
      | transpose | .[] | {t:.[0], tp:.[1], wc:.[2], pp:.[3], day:.[4], uv:.[5]} ]
    | map(select(.t >= $now)) | .[0:12] | .[]
    | [.t, (.tp|r), (if .day == 0 then "1" else "0" end), (.wc // "" | tostring), (.pp // "" | tostring), (.uv|r)] | join("\u001f")' 2>/dev/null)
  hr_build

  mapfile -t f < <(printf '%s' "$resp" | jq -r '.daily.sunrise[0] // "", .daily.sunset[0] // ""')
  R_sunrise=$(fmt_clock_dual "$(iso_epoch "${f[0]:-}")")
  R_sunset=$(fmt_clock_dual "$(iso_epoch "${f[1]:-}")")

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
  local resp night f d hi lo fcode
  resp=$(curl -sf --max-time 6 "https://wttr.in/${LAT},${LON}?format=j1") || return 1
  if is_night; then night=1; else night=0; fi

  # One pass for every scalar; field ORDER is the contract with the reads below.
  # $s is the nearest 3-hourly slot: wttr's current_condition carries neither
  # chance-of-rain nor gust, so both come from there.
  mapfile -t f < <(printf '%s' "$resp" | jq -r --argjson s "$((10#$(date +%H) / 3))" "$JQ_DEFS"'
    (.current_condition[0] // {}) as $c
    | (.weather[0] // {}) as $w
    | ($c.weatherCode // ""), ($c.temp_F // ""),
      ($c.weatherDesc[0].value // "Unknown"), ($c.FeelsLikeF // ""),
      ($c.humidity // ""), ($w.hourly[$s].chanceofrain // ""),
      ($c.windspeedMiles // ""), ($c.winddir16Point // ""),
      ($c.visibilityMiles | if . == null or . == "" then "" else (tonumber|round|tostring) end),
      ($c.uvIndex | if . == null or . == "" then "" else (tonumber|round|tostring) end),
      ($w.hourly[$s].WindGustMiles | if . == null or . == "" then "" else (tonumber|round|tostring) end),
      (if $w.astronomy[0].sunrise then ($w.date + " " + $w.astronomy[0].sunrise) else "" end),
      (if $w.astronomy[0].sunset then ($w.date + " " + $w.astronomy[0].sunset) else "" end)')
  [ -n "${f[0]:-}" ] || return 1

  R_temp="${f[1]:-}"
  R_icon=$(wttr_icon "${f[0]}" "$night")
  R_desc="${f[2]:-}"
  R_feels="${f[3]:-}"
  R_humidity="${f[4]:-}"
  R_precip="${f[5]:-}"
  R_wind="${f[6]:-}"
  R_windDir="${f[7]:-}"
  R_visibility="${f[8]:-}"
  R_uv="${f[9]:-}"
  R_windGust="${f[10]:-}"
  R_sunrise=$(fmt_clock_dual "$(iso_epoch "${f[11]:-}")")
  R_sunset=$(fmt_clock_dual "$(iso_epoch "${f[12]:-}")")

  fc_reset
  while IFS="$US" read -r d hi lo fcode; do
    [ -n "$d" ] || continue
    fc_add "$(weekday "$d")" "$(wttr_icon "$fcode" 0)" "$hi" "$lo"
  done < <(printf '%s' "$resp" | jq -r '
    .weather[0:7][]
    | [(.date // ""), (.maxtempF // ""), (.mintempF // ""),
       ((.hourly[4].weatherCode // .hourly[0].weatherCode) // "")]
    | join("\u001f")' 2>/dev/null)
  fc_build

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

# Republish the country BEFORE the cache short-circuit below. /run is cleared on
# reboot while the geo cache is not, and a weather cache hit exits early without
# ever calling resolve_geo -- so publishing only from there would leave
# consumers hintless for up to CACHE_TTL after every boot.
if [ -f "$GEO_CACHE" ]; then
  publish_country "$(jq -r '.country // ""' "$GEO_CACHE" 2>/dev/null)"
fi

# --- serve fresh per-location cache (skips geolocation entirely) --------------
if [ -f "$CACHE_FILE" ]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  fresh=0
  [ $((now - mtime)) -lt "$CACHE_TTL" ] && fresh=1
  # Only the CURRENT-location cache is invalidated by a resume. A fixed city
  # chip is pinned to coordinates that do not move: Los Angeles' weather does
  # not become wrong because this machine travelled, and expiring it here would
  # turn every wake into one API call per chip for no gain.
  if [ "$LOC_ID" = "geo" ] && predates_wake "$CACHE_FILE"; then
    fresh=0
  fi
  if [ "$fresh" = 1 ]; then
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
  # asOf 0 = never fetched. NOT the current time: this record carries no
  # observation at all, and stamping it now would render as "just updated".
  printf '{"asOf":0,"temp":"--","icon":"cloudy","desc":"Offline","source":"none","feels":"","humidity":"","precip":"","precipType":"","uv":"","wind":"","windGust":"","windDir":"","visibility":"","sunrise":"","sunset":"","place":"","forecast":[],"hourly":[],"alerts":[],"nowcast":{"rainSoon":false,"etaMin":null,"source":"none","text":""},"conditions":[]}\n'
fi
