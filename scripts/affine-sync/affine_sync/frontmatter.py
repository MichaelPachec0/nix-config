"""Minimal, dependency-free front-matter parser (subset of YAML)."""

def _coerce(v):
    v = v.strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    if v in ("true", "false"):
        return v == "true"
    if v.lstrip("-").isdigit():
        return int(v)
    return v

def split(text):
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    block = text[4:end]
    rest = text[end + 4:]
    if rest.startswith("\n"):
        rest = rest[1:]
    meta = {}
    for line in block.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, val = line.partition(":")
        meta[key.strip()] = _coerce(val)
    return meta, rest
