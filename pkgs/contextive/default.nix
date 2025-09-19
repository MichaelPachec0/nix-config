# {
#   stdenv,
#   fetchFromGitHub,
#   lib,
#   dotnet-sdk,
#   ...
# }:
# stdenv.mkDerivation (finalAttrs: rec {
#   pname = "contextive";
#   version = "v1.10.5";
#
#   src = fetchFromGitHub {
#     owner = "";
#     repo = "";
#     rev = "v${version}";
#     hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
#   };
#
#   nativeBuildInputs = [
#   ];
#   buildInputs = [
#     dotnet-sdk
#   ];
#     buildPhase = ''
#     runHook preBuild
#     cd $src
#     dotnet fsi language-server/build.fsx
#     runHook postBuild
#   '';
#   meta = {
#     description = "";
#     homepage = "";
#     license = lib.licenses.mit;
#     maintainers = with lib.maintainers; [];
#   };
# })
{ buildDotnetGlobalTool, lib }:

buildDotnetGlobalTool {
  pname = "contextive";
  version = "1.3.1";

  nugetSha256 = "sha256-ZG2HFyKYhVNVYd2kRlkbAjZJq88OADe3yjxmLuxXDUo=";

  meta = with lib; {
    homepage = "https://contextive.tech/";
    changelog = "https://cmd.petabridge.com/articles/RELEASE_NOTES.html";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
