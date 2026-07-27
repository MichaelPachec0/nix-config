"""Minimal MCP streamable-HTTP client (stdlib only)."""
import json, urllib.error, urllib.request
from . import sse

class Client:
    def __init__(self, endpoint, workspace_id, timeout=15):
        self.endpoint = endpoint
        self.workspace_id = workspace_id
        self.timeout = timeout
        self.session_id = None

    def _post(self, payload):
        headers = {"Content-Type": "application/json",
                   "Accept": "application/json, text/event-stream"}
        if self.session_id:
            headers["mcp-session-id"] = self.session_id
        req = urllib.request.Request(self.endpoint, method="POST",
                                     data=json.dumps(payload).encode("utf-8"),
                                     headers=headers)
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            sid = r.headers.get("mcp-session-id")
            if sid:
                self.session_id = sid
            return r.read().decode("utf-8")

    def connect(self):
        self._post({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                               "clientInfo": {"name": "affine-sync", "version": "1"}}})
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return self

    def reachable(self):
        try:
            self.connect()
            return True
        except (urllib.error.URLError, OSError):
            return False

    def call(self, name, arguments):
        args = dict(arguments)
        args.setdefault("workspaceId", self.workspace_id)
        body = self._post({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                           "params": {"name": name, "arguments": args}})
        return sse.result_payload(body)
