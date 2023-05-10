{ pkgs, ... }:
  pkgs.vimUtils.buildVimPlugin {
    name = "vim-be-good";
    src = pkgs.fetchFromGitHub {
      owner = "ThePrimeagen";
      repo = "vim-be-good";
      rev = "c290810728a4f75e334b07dc0f3a4cdea908d351";
      hash = "sha256-lJNY/5dONZLkxSEegrwtZ6PHYsgMD3nZkbxm6fFq3vY=";
    };
  }
