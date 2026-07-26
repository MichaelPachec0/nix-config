import unittest
from affine_sync import docspec

class Build(unittest.TestCase):
    def test_primary_kind(self):
        d = docspec.build("nix-config", "docs/e5800-router-widget/spec.md", "# S\nbody\n")
        self.assertEqual(d.feature, "e5800-router-widget")
        self.assertEqual(d.kind, "spec")
        self.assertIsNone(d.subfolder)
        self.assertEqual(d.title, "e5800-router-widget - spec")
        self.assertEqual(d.sync_key, "nix-config:docs/e5800-router-widget/spec.md")
        self.assertFalse(d.skip)
    def test_reference_name(self):
        d = docspec.build("nix-config", "docs/hy3-layout/recipes.md", "x")
        self.assertEqual(d.title, "hy3-layout - recipes")
    def test_subfolder_handoff(self):
        d = docspec.build("r", "docs/foo/handoffs/2026-07-01-bar.md", "x")
        self.assertEqual(d.subfolder, "handoffs")
        self.assertEqual(d.title, "foo - handoff 2026-07-01-bar")
    def test_frontmatter_title_and_skip(self):
        d = docspec.build("r", "docs/foo/spec.md", "---\ntitle: Custom\nskipSync: true\n---\nb\n")
        self.assertEqual(d.title, "Custom")
        self.assertTrue(d.skip)
    def test_sha_ignores_frontmatter(self):
        a = docspec.build("r", "docs/foo/spec.md", "---\norder: 1\n---\nbody\n")
        b = docspec.build("r", "docs/foo/spec.md", "body\n")
        self.assertEqual(a.sha256, b.sha256)
