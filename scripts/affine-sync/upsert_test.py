import unittest
from affine_sync import upsert
from affine_sync.docspec import DocSpec

def spec(title="foo - spec", sha="h1", body="b"):
    return DocSpec("foo", "spec", "", title, "repo:docs/foo/spec.md", body, sha, False, None)

class Fake:
    def __init__(self, matches=None, defs=None):
        self.calls = []; self.matches = matches or {}
        self.defs = defs if defs is not None else [{"id": "SK", "name": "syncKey"}]
    def call(self, name, args):
        self.calls.append((name, args))
        if name == "find_doc_by_title":
            return {"matches": self.matches.get(args["title"], [])}
        if name == "create_doc_from_markdown":
            return {"docId": "NEW"}
        if name == "list_doc_properties":
            return {"definitions": list(self.defs)}
        if name == "create_custom_property":
            return {"propertyId": "SKNEW"}
        return {}

class Upsert(unittest.TestCase):
    def test_create_when_absent(self):
        c = Fake(); st = {"docs": {}, "folders": {}}
        e = upsert.doc(c, st, "repo", spec(), "FID")
        names = [n for n, _ in c.calls]
        self.assertIn("create_doc_from_markdown", names)
        self.assertIn("add_organize_link", names)
        self.assertIn("set_doc_property", names)
        self.assertNotIn("create_custom_property", names)   # existing def reused
        sp = next(a for n, a in c.calls if n == "set_doc_property")
        self.assertEqual(sp["property"], "SK")              # set BY ID, not name
        self.assertEqual(e["docId"], "NEW")
    def test_create_makes_property_when_absent(self):
        c = Fake(defs=[]); st = {"docs": {}, "folders": {}}
        upsert.doc(c, st, "repo", spec(), "FID")
        names = [n for n, _ in c.calls]
        self.assertIn("create_custom_property", names)      # no def -> create once
        sp = next(a for n, a in c.calls if n == "set_doc_property")
        self.assertEqual(sp["property"], "SKNEW")
    def test_replace_when_in_state(self):
        c = Fake(); st = {"docs": {"docs/foo/spec.md": {"docId": "OLD", "title": "foo - spec"}}, "folders": {}}
        e = upsert.doc(c, st, "repo", spec(sha="h2"), "FID")
        names = [n for n, _ in c.calls]
        self.assertIn("replace_doc_with_markdown", names)
        self.assertNotIn("create_doc_from_markdown", names)
        self.assertEqual(e["docId"], "OLD")
    def test_reconciles_by_title_when_state_missing(self):
        c = Fake(matches={"foo - spec": [{"id": "EXIST", "inTrash": False}]})
        st = {"docs": {}, "folders": {}}
        e = upsert.doc(c, st, "repo", spec(), "FID")
        names = [n for n, _ in c.calls]
        self.assertEqual(e["docId"], "EXIST")
        self.assertIn("replace_doc_with_markdown", names)
        self.assertNotIn("create_doc_from_markdown", names)
    def test_ignores_trashed_match(self):
        c = Fake(matches={"foo - spec": [{"id": "GONE", "inTrash": True}]})
        st = {"docs": {}, "folders": {}}
        e = upsert.doc(c, st, "repo", spec(), "FID")
        self.assertEqual(e["docId"], "NEW")   # trashed match ignored -> create fresh
