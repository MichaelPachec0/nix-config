import os, tempfile, unittest
from affine_sync import engine

class FakeClient:
    def __init__(self): self.calls = []
    def reachable(self): return True
    def connect(self): return self
    def call(self, name, args):
        self.calls.append(name)
        if name == "list_organize_nodes": return {"nodes": []}
        if name == "find_doc_by_title": return {"matches": []}
        if name == "create_doc_from_markdown": return {"docId": "D"}
        if name == "read_doc": return {"title": "t"}
        return {}

class Engine(unittest.TestCase):
    def setUp(self):
        self._home = tempfile.mkdtemp()
        os.environ["AFFINE_SYNC_HOME"] = self._home   # keep tests off the real ~/.claude
    def tearDown(self):
        os.environ.pop("AFFINE_SYNC_HOME", None)
    def test_sync_changed_upserts_then_skips(self):
        with tempfile.TemporaryDirectory() as repo:
            d = os.path.join(repo, "docs", "foo"); os.makedirs(d)
            open(os.path.join(d, "spec.md"), "w").write("# S\nbody\n")
            c = FakeClient()
            cfg = {"endpoint": "E", "workspaceId": "W", "_client": c, "_repo_name": "repo"}
            engine.sync_changed(cfg, repo)                 # first run: creates
            self.assertIn("create_doc_from_markdown", c.calls)
            c.calls.clear()
            engine.sync_changed(cfg, repo)                 # second run: unchanged
            self.assertNotIn("create_doc_from_markdown", c.calls)
    def test_never_raises_when_unreachable(self):
        with tempfile.TemporaryDirectory() as repo:
            os.makedirs(os.path.join(repo, "docs", "foo"))
            open(os.path.join(repo, "docs", "foo", "spec.md"), "w").write("x")
            class Down(FakeClient):
                def reachable(self): return False
            cfg = {"endpoint": "E", "workspaceId": "W", "_client": Down(), "_repo_name": "repo"}
            engine.sync_changed(cfg, repo)  # must return without raising
    def test_bad_doc_path_does_not_abort_batch(self):
        # a flat docs/bad.md path makes docspec.build raise; the valid doc must still sync
        with tempfile.TemporaryDirectory() as repo:
            os.makedirs(os.path.join(repo, "docs", "foo"))
            open(os.path.join(repo, "docs", "bad.md"), "w").write("flat path -> raises")
            open(os.path.join(repo, "docs", "foo", "spec.md"), "w").write("# ok\nbody\n")
            c = FakeClient()
            cfg = {"endpoint": "E", "workspaceId": "W", "_client": c, "_repo_name": "repo"}
            engine.sync_changed(cfg, repo)                 # bad.md sorts first; must not abort
            self.assertIn("create_doc_from_markdown", c.calls)  # foo/spec.md still synced
    def test_title_only_change_resyncs(self):
        with tempfile.TemporaryDirectory() as repo:
            d = os.path.join(repo, "docs", "foo"); os.makedirs(d)
            fp = os.path.join(d, "spec.md")
            open(fp, "w").write("# S\nbody\n")
            c = FakeClient()
            cfg = {"endpoint": "E", "workspaceId": "W", "_client": c, "_repo_name": "repo"}
            engine.sync_changed(cfg, repo)                       # first: create
            c.calls.clear()
            open(fp, "w").write("---\ntitle: New Title\n---\n# S\nbody\n")  # title-only (body same)
            engine.sync_changed(cfg, repo)
            self.assertIn("update_doc_title", c.calls)           # title change propagated
