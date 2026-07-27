"""Parse the affine-mcp streamable-HTTP SSE response body."""
import json

class McpError(Exception):
    pass

def frames(body):
    out = []
    for line in body.splitlines():
        if line.startswith("data:"):
            payload = line[5:].strip()
            if payload:
                out.append(json.loads(payload))
    return out

def result_payload(body):
    for fr in frames(body):
        if "error" in fr:                       # JSON-RPC transport error
            raise McpError(str(fr["error"]))
        if "result" in fr:
            res = fr["result"]
            content = res.get("content") or []
            text = content[0].get("text", "") if content else ""
            if res.get("isError"):              # tool error: text is a plain string
                raise McpError(text or "tool error")
            if res.get("structuredContent") is not None:
                return res["structuredContent"]
            if content and content[0].get("type") == "text":
                return json.loads(text)
            return res
    raise McpError("no result frame in response")
