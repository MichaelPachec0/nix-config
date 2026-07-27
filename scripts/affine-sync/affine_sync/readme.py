"""Pure render of the workspace index into the README markdown."""

def render(index, meta, template):
    lines = [template.rstrip("\n"), "", "## Projects", ""]
    n_repos = n_features = n_docs = 0
    for repo in index["repos"]:
        n_repos += 1
        feats = repo["features"]
        rdocs = sum(len(f["docs"]) for f in feats)
        lines.append("### {}  --  {} features, {} docs".format(repo["name"], len(feats), rdocs))
        for f in feats:
            n_features += 1
            n_docs += len(f["docs"])
            kinds = ", ".join(d["title"].split(" - ", 1)[-1] for d in f["docs"])
            lines.append("- {}  --  {} ({} docs)".format(f["name"], kinds, len(f["docs"])))
        lines.append("")
    lines += ["## Metadata", "",
              "- Workspace id: {}".format(meta["workspaceId"]),
              "- Endpoint: {}".format(meta["endpoint"]),
              "- Totals: {} repos, {} features, {} docs".format(n_repos, n_features, n_docs),
              "- Generated: {}".format(meta["generatedAt"]), ""]
    return "\n".join(lines) + "\n"
