{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  pname = "git.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "dinhhuy258";
    repo = "git.nvim";
    rev = "741696687486f25f8b73d9e4c76ab2ede9998f39";
    hash = "sha256-LPSS/76pMxWyB9dsGmHb06iER2ctWSLHyD+RV+2n+xs=";
  };
}
