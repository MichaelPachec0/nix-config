"""Orchestration + fail-soft entrypoints."""
import datetime, glob, os
from . import config, docspec, folders, mcp, readme, state, upsert

STATE_FILE = ".affine-sync.json"

def _home():
    # State/log/template/mirror dir; env override keeps unit tests off the real ~/.claude.
    return os.environ.get("AFFINE_SYNC_HOME", os.path.expanduser("~/.claude/affine-sync"))

def _log(msg):
    try:
        os.makedirs(_home(), exist_ok=True)
        with open(os.path.join(_home(), "sync.log"), "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except OSError:
        pass

def _now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def _client(cfg):
    if cfg.get("_client"):
        return cfg["_client"]
    return mcp.Client(cfg["endpoint"], cfg["workspaceId"])

def _repo_name(cfg, repo_dir):
    return cfg.get("_repo_name") or config.repo_name(repo_dir)

def _docs(repo_dir):
    return sorted(p for p in glob.glob(os.path.join(repo_dir, "docs", "**", "*.md"),
                                       recursive=True))

def _sync_one(client, st, repo, repo_dir, path):
    relpath = os.path.relpath(path, repo_dir)
    text = open(path, "r", encoding="utf-8").read()
    spec = docspec.build(repo, relpath, text)
    if spec.skip:
        return False
    if state.unchanged(st, relpath, spec.sha256):
        return False
    fid = folders.ensure(client, st, repo, spec.feature)
    entry = upsert.doc(client, st, repo, spec, fid)
    entry["syncedAt"] = _now()
    state.record(st, relpath, entry)
    _log("{} sync {} {}".format(_now(), repo, relpath))
    return True

def sync_changed(cfg, repo_dir, force_all=False):
    try:
        client = _client(cfg)
        if not client.reachable():
            _log("{} skip {} unreachable".format(_now(), repo_dir))
            return
        repo = _repo_name(cfg, repo_dir)
        sp = os.path.join(repo_dir, STATE_FILE)
        st = state.load(sp)
        st["workspaceId"] = cfg["workspaceId"]
        _ensure_property(client)
        changed = False
        for path in _docs(repo_dir):
            if force_all:
                relpath = os.path.relpath(path, repo_dir)
                st["docs"].get(relpath, {}).pop("sha256", None)
            changed = _sync_one(client, st, repo, repo_dir, path) or changed
        state.save(sp, st)
        if changed:
            build_readme(cfg, client, st)
    except Exception as e:            # fail-soft: never propagate
        _log("{} ERROR {} {}".format(_now(), repo_dir, e))

def sync_all(cfg, repo_dir):
    sync_changed(cfg, repo_dir, force_all=True)

def sync_file(cfg, repo_dir, relpath):
    try:
        client = _client(cfg)
        if not client.reachable():
            _log("{} skip file {} unreachable".format(_now(), relpath))
            return
        repo = _repo_name(cfg, repo_dir)
        sp = os.path.join(repo_dir, STATE_FILE)
        st = state.load(sp); st["workspaceId"] = cfg["workspaceId"]
        _ensure_property(client)
        if _sync_one(client, st, repo, repo_dir, os.path.join(repo_dir, relpath)):
            state.save(sp, st)
            build_readme(cfg, client, st)
    except Exception as e:
        _log("{} ERROR file {} {}".format(_now(), relpath, e))

def _ensure_property(client):
    # Ensure the workspace-wide syncKey text property exists (idempotent per spike).
    try:
        client.call("create_custom_property", {"name": "syncKey", "type": "text"})
    except Exception:
        pass   # already exists (or transient) -> fine

def _build_index(client, state_data):
    # Build the repo->feature->docs index from the ORGANIZE-FOLDER tree.
    # list_workspace_tree is blind to organize folders (spike) -> use list_organize_nodes:
    # a flat list; group by parentId; folder display name is in `data`; a type:"doc"
    # node's `data` is the target docId.
    nodes = client.call("list_organize_nodes", {}).get("nodes", [])
    by_parent = {}
    for n in nodes:
        by_parent.setdefault(n.get("parentId"), []).append(n)
    # docId -> title: local state is the fast path; read_doc is the fallback
    # (get_doc/list_docs are server-broken -- see spike).
    cache = {e["docId"]: e.get("title")
             for e in (state_data or {}).get("docs", {}).values() if e.get("docId")}
    def title_for(docid):
        if cache.get(docid):
            return cache[docid]
        try:
            return client.call("read_doc", {"docId": docid}).get("title") or docid
        except Exception:
            return docid
    repos = []
    for repo_n in sorted((n for n in by_parent.get(None, []) if n.get("type") == "folder"),
                         key=lambda n: n.get("data", "")):
        feats = []
        for feat_n in sorted((n for n in by_parent.get(repo_n["id"], []) if n.get("type") == "folder"),
                             key=lambda n: n.get("data", "")):
            docs = [{"title": title_for(d["data"])}
                    for d in by_parent.get(feat_n["id"], []) if d.get("type") == "doc"]
            docs.sort(key=lambda d: d["title"])
            feats.append({"name": feat_n.get("data", ""), "docs": docs})
        repos.append({"name": repo_n.get("data", ""), "features": feats})
    return {"repos": repos}

def build_readme(cfg, client, state_data=None):
    try:
        index = _build_index(client, state_data)
        tpl_path = os.path.join(_home(), "readme-template.md")
        template = open(tpl_path, encoding="utf-8").read() if os.path.exists(tpl_path) else "# Workspace Guide (README)\n"
        meta = {"workspaceId": cfg["workspaceId"], "endpoint": cfg["endpoint"],
                "generatedAt": _now()}
        body = readme.render(index, meta, template)
        mirror = os.path.join(_home(), "README.md")
        prev = open(mirror, encoding="utf-8").read() if os.path.exists(mirror) else ""
        if _strip_generated(prev) == _strip_generated(body):   # avoid churn
            return
        res = client.call("find_doc_by_title", {"title": "README"})
        live = [m for m in res.get("matches", []) if not m.get("inTrash")]
        if live:
            client.call("replace_doc_with_markdown", {"docId": live[0]["id"], "markdown": body})
        else:
            client.call("create_doc_from_markdown", {"title": "README", "markdown": body})
        os.makedirs(_home(), exist_ok=True)
        open(mirror, "w", encoding="utf-8").write(body)
        _log("{} readme regenerated".format(_now()))
    except Exception as e:
        _log("{} ERROR readme {}".format(_now(), e))

def _strip_generated(text):
    return "\n".join(l for l in text.splitlines() if not l.startswith("- Generated:"))
