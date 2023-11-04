{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "nvim-dap-repl-highlights";
  version = "0.0.1-master";

  src = pkgs.fetchFromGitHub {
    owner = "liadoz";
    repo = pname;
    rev = "97a2b322c05cf945c5aabaad5e599a20b25e77d9";
    hash = "sha256-BtMTgL2laIyirlEG1xgghLd1oU1hFFFPBK+0jaHNpbI=";
  };
}
