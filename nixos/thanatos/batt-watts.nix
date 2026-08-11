{
  pkgs,
  lib,
  ...
}: let
  battWatts =
    pkgs.runCommand "batt-watts" {
      nativeBuildInputs = [pkgs.shellcheck pkgs.makeWrapper];
    } ''
      cp ${./batt-watts/batt-watts.sh} batt-watts.sh
      cp ${./batt-watts/test_batt-watts.sh} test_batt-watts.sh
      shellcheck batt-watts.sh test_batt-watts.sh
      bash test_batt-watts.sh ./batt-watts.sh
      install -Dm755 batt-watts.sh "$out/bin/batt-watts"
      wrapProgram "$out/bin/batt-watts" --prefix PATH : ${lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
      ]}
    '';
in {
  environment.systemPackages = [battWatts];
}
