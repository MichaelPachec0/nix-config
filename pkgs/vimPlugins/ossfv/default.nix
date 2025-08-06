{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "one-small-step-for-vimkind";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "jbyuki";
    repo = "one-small-step-for-vimkind";
    rev = "edbb34ee779049f2071dc7becff0bbf51c865906";
    hash = "sha256-Esy9VjG9J86vDJjjLtlLChTc2710ynwcDxgnMc9gizs=";
  };
}
