# Packaging helper: places the shared hypr_ipc.py module in its own store
# directory so a daemon's writeShellApplication can add it to PYTHONPATH. Nix
# copies a single `.py` file to the store under a hashed basename, so a sibling
# `import hypr_ipc` needs the module co-located in a real directory. Imported by
# hypr-monitor-arrange.nix, hypr-window-keeper.nix, and hypr-scratchpad-guard.nix
# (identical derivation -> shared store path, built once).
{pkgs}:
pkgs.runCommand "hypr-ipc-py" {} ''
  mkdir -p $out
  cp ${./hypr_ipc.py} $out/hypr_ipc.py
''
