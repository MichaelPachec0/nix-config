#!/usr/bin/env bash
# Runs scripts/ntfy-send.sh against a local one-shot HTTP server that
# records the request. Needs python3 and curl on PATH.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/ntfy-send.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; kill "${srv:-}" 2>/dev/null || true' EXIT

mkdir -p "$tmp/creds"
printf 'tok-123' > "$tmp/creds/ntfy-token"
printf 'my-topic' > "$tmp/creds/ntfy-topic"

cat > "$tmp/server.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n).decode()
        with open(sys.argv[2], "w") as f:
            f.write(f"path={self.path}\n")
            for k in ("Authorization", "Title", "Priority", "Tags"):
                f.write(f"{k}={self.headers.get(k)}\n")
            f.write(f"body={body}\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).handle_request()
PY

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 "$tmp/server.py" "$port" "$tmp/seen" & srv=$!
sleep 0.5

echo "case 1: request carries token, topic, headers, body"
printf 'line one\nline two\n' | CREDENTIALS_DIRECTORY="$tmp/creds" NTFY_URL="http://127.0.0.1:$port" \
  bash "$script" "kore: boot fallback" high rotating_light
grep -q '^path=/my-topic$' "$tmp/seen"
grep -q '^Authorization=Bearer tok-123$' "$tmp/seen"
grep -q '^Title=kore: boot fallback$' "$tmp/seen"
grep -q '^Priority=high$' "$tmp/seen"
grep -q '^Tags=rotating_light$' "$tmp/seen"
grep -q 'body=line one' "$tmp/seen"
grep -q '^line two$' "$tmp/seen"
echo "case 1 ok"

echo "case 2: unreachable server retries then fails non-zero"
if printf 'x' | CREDENTIALS_DIRECTORY="$tmp/creds" NTFY_URL="http://127.0.0.1:1" NTFY_RETRIES=2 NTFY_RETRY_SLEEP=0 \
  bash "$script" t default none; then echo "expected failure"; exit 1; fi
echo "case 2 ok"
echo "all ntfy-send cases passed"
