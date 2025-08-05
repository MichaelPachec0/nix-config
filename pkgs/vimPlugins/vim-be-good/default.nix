{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "vim-be-good";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "ThePrimeagen";
    repo = pname;
    rev = "c290810728a4f75e334b07dc0f3a4cdea908d351";
    hash = "sha256-lJNY/5dONZLkxSEegrwtZ6PHYsgMD3nZkbxm6fFq3vY=";
  };
}
