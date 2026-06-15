{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  ...
}:
buildNpmPackage rec {
  pname = "emmet-language-server";
  version = "v2.3.0-pre";
  src = fetchFromGitHub {
    owner = "olrtg";
    repo = pname;
    rev = "949a69ee71367e5517559ae3a7cb8e96c7e5f9f4";
    hash = "sha256-Qw83EinvLExfmpzUq7Hu7+DEnl7cZIVKAYNN/E/Eocs=";
  };
  npmDepsHash = lib.fakeHash;
}
