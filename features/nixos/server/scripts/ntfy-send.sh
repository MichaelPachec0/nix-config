# ntfy-send TITLE PRIORITY TAGS  < body
#
# Posts one ntfy.sh message. Token and topic come from systemd credentials
# ($CREDENTIALS_DIRECTORY/ntfy-token, /ntfy-topic), never from the store or
# the environment. The token reaches curl through a private, mode-0600
# header file (curl's `-H @file` form), never as a literal argv argument,
# since argv is readable by any local user via ps or /proc/<pid>/cmdline.
# The body is buffered to a temp file so every retry sends the same bytes.
# Retries because the alert is the whole point and the host may have just
# come back from a fallback with a flapping uplink.
#
# Env: NTFY_URL (https://ntfy.sh), NTFY_RETRIES (5), NTFY_RETRY_SLEEP (30).
set -euo pipefail

title=${1:?title}
priority=${2:-default}
tags=${3:-}
creds=${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY unset; run under systemd LoadCredential}
token=$(cat "$creds/ntfy-token")
topic=$(cat "$creds/ntfy-topic")
url="${NTFY_URL:-https://ntfy.sh}/$topic"
retries=${NTFY_RETRIES:-5}
pause=${NTFY_RETRY_SLEEP:-30}

body=$(mktemp)
hdrfile=$(mktemp)
chmod 600 "$hdrfile"
printf 'Authorization: Bearer %s\n' "$token" > "$hdrfile"
trap 'rm -f "$body" "$hdrfile"' EXIT
cat > "$body"

attempt=1
while :; do
  if curl -fsS --max-time 20 \
      -H "@$hdrfile" \
      -H "Title: $title" \
      -H "Priority: $priority" \
      -H "Tags: $tags" \
      --data-binary "@$body" \
      "$url" > /dev/null; then
    echo "ntfy-send: delivered '$title' (attempt $attempt)"
    exit 0
  fi
  if [ "$attempt" -ge "$retries" ]; then
    echo "ntfy-send: giving up on '$title' after $attempt attempts" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep "$pause"
done
