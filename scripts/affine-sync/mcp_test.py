import unittest
from affine_sync import mcp

class FakeClient(mcp.Client):
    def __init__(self):
        super().__init__("http://x/mcp", "WS")
        self.sent = []
    def _post(self, payload):
        self.sent.append(payload)
        # emulate a tools/call SSE body echoing the workspaceId it received
        args = payload.get("params", {}).get("arguments", {})
        return ('event: message\ndata: {"result":{"content":[{"type":"text",'
                '"text":"{\\"ws\\":\\"%s\\"}"}]},"jsonrpc":"2.0","id":2}\n\n' % args.get("workspaceId", ""))

class Call(unittest.TestCase):
    def test_call_injects_workspace_id(self):
        c = FakeClient()
        out = c.call("list_docs", {})
        self.assertEqual(out, {"ws": "WS"})
        self.assertEqual(c.sent[-1]["params"]["arguments"]["workspaceId"], "WS")
