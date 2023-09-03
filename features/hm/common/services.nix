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
    {
      services =
        lib.recursiveUpdate {}
        (lib.attrsets.optionalAttrs config.audio.enable {
          playerctld.enable = true;
        });
    }
    // lib.mkIf config.report-changes.enable {
      home.activation.report-changes = dag.entryAnywhere ''
        ${lib.getExe pkgs.nvd} diff $oldGenPath $newGenPath
      '';
    };
}
