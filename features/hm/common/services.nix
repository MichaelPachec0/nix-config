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
        home.activation.report-changes = dag.entryAnywhere ''
          ${lib.getExe pkgs.nvd} diff $oldGenPath $newGenPath
        '';
      })
    ];
}
