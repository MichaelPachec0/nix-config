{
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "qs-greeter";
  version = "0.1.0";
  src = ./greeter;

  # dev/ is a sibling of greeter/, so it is structurally excluded: `src` points
  # at greeter/ only. The mock greetd backend must never exist on a deployed
  # system -- an env-gated fake auth path would be one stray EnvironmentFile
  # away from a login bypass.
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/greeter"
    cp -r ./. "$out/greeter/"
    runHook postInstall
  '';

  meta = {
    description = "Quickshell greetd greeter (QML tree)";
    platforms = lib.platforms.linux;
  };
}
