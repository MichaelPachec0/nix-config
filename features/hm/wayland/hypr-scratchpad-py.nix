# Packaging helper: co-locates hypr_ipc.py and scratchpad_cycle.py in one store
# directory so the resident scratchpad guard can `import` both (scratchpad_cycle
# itself imports hypr_ipc, and the guard now calls its functions in-process
# instead of spawning python). Same idea as hypr-ipc-py.nix, one module wider.
# Imported by hypr-scratchpad-guard.nix for PYTHONPATH.
{pkgs}:
pkgs.runCommand "hypr-scratchpad-py" {} ''
  mkdir -p $out
  cp ${./hypr_ipc.py} $out/hypr_ipc.py
  cp ${./scratchpad_cycle.py} $out/scratchpad_cycle.py
''
