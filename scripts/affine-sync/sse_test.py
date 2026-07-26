import unittest
from affine_sync import sse

# text-only payload (structuredContent absent) -> decode content[0].text
TOOL_TEXT = 'event: message\ndata: {"result":{"content":[{"type":"text","text":"{\\"id\\":\\"D1\\"}"}]},"jsonrpc":"2.0","id":2}\n\n'
# structuredContent present -> prefer it
TOOL_STRUCT = 'event: message\ndata: {"result":{"content":[{"type":"text","text":"{}"}],"structuredContent":{"docId":"D2"}},"jsonrpc":"2.0","id":2}\n\n'
# broken-tool error: isError result, content[0].text is a plain error STRING
TOOL_ISERR = 'event: message\ndata: {"result":{"content":[{"type":"text","text":"GraphQL error: boom"}],"isError":true},"jsonrpc":"2.0","id":2}\n\n'
# transport-level JSON-RPC error frame
TOOL_RPCERR = 'event: message\ndata: {"error":{"code":-32000,"message":"boom"},"jsonrpc":"2.0","id":2}\n\n'

class Sse(unittest.TestCase):
    def test_frames(self):
        self.assertEqual(sse.frames(TOOL_TEXT)[0]["id"], 2)
    def test_result_payload_text(self):
        self.assertEqual(sse.result_payload(TOOL_TEXT), {"id": "D1"})
    def test_result_payload_prefers_structured(self):
        self.assertEqual(sse.result_payload(TOOL_STRUCT), {"docId": "D2"})
    def test_iserror_result_raises_with_text(self):
        with self.assertRaises(sse.McpError) as cm:
            sse.result_payload(TOOL_ISERR)
        self.assertIn("GraphQL error", str(cm.exception))
    def test_rpc_error_raises(self):
        with self.assertRaises(sse.McpError):
            sse.result_payload(TOOL_RPCERR)
