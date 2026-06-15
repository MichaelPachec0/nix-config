# WARN: For now this is WIP, do not commit status, as this does not the ability to setup n-gram data. and ltrs at least will default
#   to the public language api, that being said, it would be apt in the future to migrate to private language server.
{
  lib,
  config,
  ...
}: let
  cfg = config;
in
  with lib; {
    options = {
      languageTool.bare.enable = mkEnableOption "Enable languageTool server";
      languageTool.container.enable = mkEnableOption "Enable languageTool in a container";
    };
    config =
      (mkIf cfg.languageTool.bare.enable {
        services.languagetool = {
          enable = true;
          # NOTE: public in this case means that outside of localhost. This should be exposed in the overlay network.
          public = true;
          port = 6060;
          settings = {
            cacheSize = 10000;
          };
        };
      }
      // {
        services.eternal-terminal.enable = true;
      });
  }
