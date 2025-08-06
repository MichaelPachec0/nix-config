{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "pfp-vim";
  version = "2024-01-27-master";
  src = pkgs.fetchFromGitHub {
    owner = "d0c-s4vage";
    repo = pname;
    rev = "a7a598e91408f9edb01089ecf44bae72bb7d197b";
    hash = "sha256-K1JwjVYj16aB7sH/9xsqHyniuX8cRQoonfVa/543hLY=";
  };
}
