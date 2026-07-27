import json, os, tempfile, unittest
from affine_sync import config

class Config(unittest.TestCase):
    def test_load_from_env_path(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "config.json")
            json.dump({"endpoint": "E", "workspaceId": "W"}, open(p, "w"))
            os.environ["AFFINE_SYNC_CONFIG"] = p
            try:
                c = config.load()
                self.assertEqual(c["endpoint"], "E")
            finally:
                del os.environ["AFFINE_SYNC_CONFIG"]
    def test_repo_name_override(self):
        with tempfile.TemporaryDirectory() as t:
            json.dump({"repoName": "custom"}, open(os.path.join(t, ".affine-sync.json"), "w"))
            self.assertEqual(config.repo_name(t), "custom")
