"""Pure mapping from a repo doc path + content to its AFFiNE identity."""
import hashlib
from dataclasses import dataclass
from . import frontmatter

@dataclass
class DocSpec:
    feature: str
    kind: str
    subfolder: str
    title: str
    sync_key: str
    body: str
    sha256: str
    skip: bool
    order: int

def build(repo, relpath, text):
    meta, body = frontmatter.split(text)
    parts = relpath.split("/")
    if len(parts) < 3 or parts[0] != "docs":
        raise ValueError("not a docs/<feature>/... path: " + relpath)
    feature = parts[1]
    if len(parts) == 3:
        subfolder = None
        kind = parts[2][:-3] if parts[2].endswith(".md") else parts[2]
        auto_title = "{} - {}".format(feature, kind)
    else:
        subfolder = parts[2]
        stem = parts[-1][:-3] if parts[-1].endswith(".md") else parts[-1]
        kind = subfolder[:-1] if subfolder.endswith("s") else subfolder
        auto_title = "{} - {} {}".format(feature, kind, stem)
    title = meta.get("title", auto_title)
    sha = hashlib.sha256(body.encode("utf-8")).hexdigest()
    return DocSpec(
        feature=feature, kind=kind, subfolder=subfolder, title=title,
        sync_key="{}:{}".format(repo, relpath), body=body, sha256=sha,
        skip=bool(meta.get("skipSync", False)),
        order=meta.get("order") if isinstance(meta.get("order"), int) else None,
    )
