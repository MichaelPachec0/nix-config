import unittest
from affine_sync import folders

class FakeClient:
    def __init__(self):
        self.nodes = []       # {id, parentId, type, data}  (spike-confirmed shape)
        self.calls = []
        self._n = 0
    def call(self, name, args):
        self.calls.append((name, args))
        if name == "list_organize_nodes":
            return {"nodes": [dict(n) for n in self.nodes]}
        if name == "create_folder":
            self._n += 1
            fid = "id%d" % self._n
            self.nodes.append({"id": fid, "parentId": args.get("parentId"),
                               "type": "folder", "data": args["name"]})
            return {"id": fid}   # engine re-lists rather than trusting this
        raise AssertionError(name)

class Ensure(unittest.TestCase):
    def test_creates_repo_and_feature_then_caches(self):
        c = FakeClient(); st = {"folders": {}}
        fid = folders.ensure(c, st, "nix-config", "quickshell")
        self.assertEqual(st["folders"]["nix-config/quickshell"], fid)
        self.assertIn("nix-config", st["folders"])
        creates = [a for n, a in c.calls if n == "create_folder"]
        self.assertEqual(len(creates), 2)        # repo + feature
        folders.ensure(c, st, "nix-config", "quickshell")  # fully cached now
        self.assertEqual(len([a for n, a in c.calls if n == "create_folder"]), 2)
    def test_reuses_existing_server_folders_matched_by_data(self):
        c = FakeClient()
        c.nodes = [{"id": "R", "parentId": None, "type": "folder", "data": "nix-config"},
                   {"id": "F", "parentId": "R", "type": "folder", "data": "quickshell"}]
        st = {"folders": {}}
        fid = folders.ensure(c, st, "nix-config", "quickshell")
        self.assertEqual(fid, "F")
        self.assertEqual([n for n, _ in c.calls].count("create_folder"), 0)
