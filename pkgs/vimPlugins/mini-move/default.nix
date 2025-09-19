{
  pkgs,
  lib,
  ...
}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "mini.move";
  version = "v0.10.0";
  src = pkgs.fetchFromGitHub {
    owner = "echasnovski";
    repo = pname;
    rev = "v${version}";
    hash = lib.fakeHash;
  };
}
