import unittest
from affine_sync import frontmatter

class Split(unittest.TestCase):
    def test_no_frontmatter(self):
        self.assertEqual(frontmatter.split("# Title\nbody\n"), ({}, "# Title\nbody\n"))
    def test_basic(self):
        meta, body = frontmatter.split("---\ntitle: Hi\norder: 10\nskipSync: true\n---\n# B\n")
        self.assertEqual(meta, {"title": "Hi", "order": 10, "skipSync": True})
        self.assertEqual(body, "# B\n")
    def test_quoted_value_and_colon(self):
        meta, _ = frontmatter.split('---\ntitle: "a: b"\n---\nx\n')
        self.assertEqual(meta["title"], "a: b")
