"""Ensure the <repo>/<feature> organize-folder path exists; cache ids in state.

list_organize_nodes returns a FLAT list (spike-confirmed): each node is
{id, parentId, type: "folder"|"doc", data, index}. The folder's display name is
in `data` (NOT `name`); root folders have parentId=None. After create_folder we
re-list to read the authoritative id (do not trust create_folder's response shape).
"""

def _nodes(client):
    res = client.call("list_organize_nodes", {})
    return res.get("nodes", []) if isinstance(res, dict) else (res or [])

def _find_folder(nodes, name, parent_id):
    for n in nodes:
        if n.get("type") == "folder" and n.get("data") == name and n.get("parentId") == parent_id:
            return n.get("id")
    return None

def _ensure_folder(client, name, parent_id):
    fid = _find_folder(_nodes(client), name, parent_id)
    if fid:
        return fid
    args = {"name": name}
    if parent_id is not None:
        args["parentId"] = parent_id
    client.call("create_folder", args)
    return _find_folder(_nodes(client), name, parent_id)   # re-list for the real id

def ensure(client, state_data, repo, feature):
    folders = state_data.setdefault("folders", {})
    feat_key = "{}/{}".format(repo, feature)
    if folders.get(feat_key):
        return folders[feat_key]
    repo_id = folders.get(repo) or _ensure_folder(client, repo, None)
    folders[repo] = repo_id
    feat_id = _ensure_folder(client, feature, repo_id)
    folders[feat_key] = feat_id
    return feat_id
