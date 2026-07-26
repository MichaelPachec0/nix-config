"""Idempotent create-or-replace of a single doc under its feature folder."""

def _relpath(spec):
    return spec.sync_key.split(":", 1)[1]

def _reconcile(client, spec):
    # spike-confirmed shape: {"matches":[{id, title, inTrash, ...}]}; id IS the docId.
    res = client.call("find_doc_by_title", {"title": spec.title})
    matches = res.get("matches", []) if isinstance(res, dict) else (res or [])
    live = [m for m in matches if not m.get("inTrash")]
    if len(live) == 1:
        return live[0].get("id")
    return None

def doc(client, state_data, repo, spec, folder_id):
    relpath = _relpath(spec)
    doc_id = state_data.get("docs", {}).get(relpath, {}).get("docId")
    prev_title = state_data.get("docs", {}).get(relpath, {}).get("title")
    if not doc_id:
        doc_id = _reconcile(client, spec)
    if not doc_id:
        res = client.call("create_doc_from_markdown",
                          {"title": spec.title, "markdown": spec.body})
        doc_id = res.get("docId") or res.get("id")
        client.call("add_organize_link",
                    {"folderId": folder_id, "type": "doc", "targetId": doc_id})
        client.call("set_doc_property",
                    {"docId": doc_id, "property": "syncKey", "value": spec.sync_key})
    else:
        client.call("replace_doc_with_markdown",
                    {"docId": doc_id, "markdown": spec.body})
        if prev_title and prev_title != spec.title:
            client.call("update_doc_title", {"docId": doc_id, "title": spec.title})
    return {"docId": doc_id, "folderId": folder_id, "sha256": spec.sha256,
            "title": spec.title}
