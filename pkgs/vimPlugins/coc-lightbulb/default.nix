{ pkgs, ... }:
pkgs.vimUtils.buildVimPlugin rec {
  name = "coc-lightbulb";
  src = pkgs.fetchFromGitHub {
    owner = "xiyaowong";
    repo = "${name}-";
    rev = "b19d5330ad0e2cb663c2667ecc73b3a6cf04c24f";
    sha256 = "88SQqsmchp5s6D4beK5Ic96EqbrPkaqYTL7SifY3Mdg=";
  };
}
