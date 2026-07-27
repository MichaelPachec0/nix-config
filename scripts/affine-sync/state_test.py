import os, tempfile, unittest
from affine_sync import state

class State(unittest.TestCase):
    def test_load_missing_returns_empty(self):
        d = state.load("/nonexistent/x.json")
        self.assertEqual(d["docs"], {})
        self.assertEqual(d["version"], 1)
    def test_roundtrip_and_unchanged(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "s.json")
            d = state.load(p)
            state.record(d, "docs/f/spec.md", {"docId": "D", "folderId": "F", "sha256": "abc", "title": "T", "syncedAt": "now"})
            state.save(p, d)
            d2 = state.load(p)
            self.assertEqual(state.doc_id(d2, "docs/f/spec.md"), "D")
            self.assertTrue(state.unchanged(d2, "docs/f/spec.md", "abc"))
            self.assertFalse(state.unchanged(d2, "docs/f/spec.md", "def"))
            self.assertFalse(state.unchanged(d2, "docs/other.md", "abc"))
