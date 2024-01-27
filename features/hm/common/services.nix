{
  config,
  lib,
  ...
}: {
  options = {};
  config = {
    services =
      lib.recursiveUpdate {}
      (lib.attrsets.optionalAttrs (config.audio.enable) {
        playerctld.enable = true;
      });
  };
}
