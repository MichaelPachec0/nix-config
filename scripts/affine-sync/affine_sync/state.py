"""Per-repo sync state: the authoritative identity + change-detection store."""
import json, os

def load(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (FileNotFoundError, ValueError):
        data = {}
    data.setdefault("version", 1)
    data.setdefault("workspaceId", "")
    data.setdefault("folders", {})
    data.setdefault("docs", {})
    return data

def save(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)

def doc_id(data, relpath):
    return data["docs"].get(relpath, {}).get("docId")

def unchanged(data, relpath, sha):
    return data["docs"].get(relpath, {}).get("sha256") == sha

def record(data, relpath, entry):
    data["docs"][relpath] = entry
