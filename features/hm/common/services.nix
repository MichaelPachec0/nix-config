{
  config,
  lib,
  pkgs,
  ...
}: {
  options = {};
  config = let
    inherit (config.lib) dag;
  in
    lib.mkMerge [
      (lib.mkIf config.audio.enable {
        services.playerctld.enable = true;
      })
      (lib.mkIf config.report-changes.enable {
        # activate runs under `set -u` and leaves oldGenPath unset when the
        # current-home gcroot is missing or dangling (first run, or its target was
        # garbage collected). A bare $oldGenPath then aborts the whole activation
        # before the gcroot is rewritten, so it can never heal. Guard the
        # expansion and never let the report fail the switch.
        home.activation.report-changes = dag.entryAnywhere ''
          if [[ -n "''${oldGenPath:-}" ]]; then
            ${lib.getExe pkgs.nvd} diff "$oldGenPath" "$newGenPath" || true
          else
            echo "report-changes: no previous generation to diff against"
          fi
        '';
      })
    ];
}
