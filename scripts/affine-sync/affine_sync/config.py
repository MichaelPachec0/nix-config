"""Machine config + per-repo naming."""
import json, os, subprocess

class ConfigError(Exception):
    pass

def _config_path():
    return os.environ.get("AFFINE_SYNC_CONFIG",
                          os.path.expanduser("~/.claude/affine-sync/config.json"))

def load():
    p = _config_path()
    try:
        with open(p, "r", encoding="utf-8") as f:
            c = json.load(f)
    except FileNotFoundError:
        raise ConfigError("missing config: " + p)
    for k in ("endpoint", "workspaceId"):
        if not c.get(k):
            raise ConfigError("config missing key: " + k)
    return c

def repo_name(repo_dir):
    override = os.path.join(repo_dir, ".affine-sync.json")
    if os.path.exists(override):
        try:
            v = json.load(open(override)).get("repoName")
            if v:
                return v
        except ValueError:
            pass
    top = subprocess.run(["git", "-C", repo_dir, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    base = top.stdout.strip() or repo_dir
    return os.path.basename(base.rstrip("/"))
