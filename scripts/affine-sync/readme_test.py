import unittest
from affine_sync import readme

TEMPLATE = "# Workspace Guide (README)\n\nHEAD\n"
# docs carry only {title}; per-doc timestamps are omitted (get_doc/list_docs broken,
# updatedAt unreliable -- see Task 1 spike contract).
INDEX = {"repos": [
    {"name": "nix-config", "features": [
        {"name": "e5800-router-widget", "docs": [
            {"title": "e5800-router-widget - spec"},
            {"title": "e5800-router-widget - plan"}]},
        {"name": "quickshell", "docs": [
            {"title": "quickshell - review"}]}]}]}
META = {"workspaceId": "2f9183ef", "endpoint": "http://127.0.0.1:7021/mcp", "generatedAt": "2026-07-25T00:00:00Z"}

class Render(unittest.TestCase):
    def test_contains_head_projects_and_metadata(self):
        out = readme.render(INDEX, META, TEMPLATE)
        self.assertIn("HEAD", out)
        self.assertIn("## Projects", out)
        self.assertIn("### nix-config", out)
        self.assertIn("e5800-router-widget", out)
        self.assertIn("spec, plan", out)      # kinds derived from titles
        self.assertIn("2 docs", out)          # feature doc count
        self.assertIn("## Metadata", out)
        self.assertIn("2f9183ef", out)
        self.assertIn("1 repos, 2 features, 3 docs", out)  # totals
    def test_deterministic(self):
        self.assertEqual(readme.render(INDEX, META, TEMPLATE),
                         readme.render(INDEX, META, TEMPLATE))
