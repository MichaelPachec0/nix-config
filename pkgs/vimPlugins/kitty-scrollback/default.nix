{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "kitty-scrollback.nvim";
  version = "6.2.0";
  src = pkgs.fetchFromGitHub {
    owner = "mikesmithgh";
    repo = pname;
    rev = "9f4e0684255efdc15f419e6aeba20289f49367ba";
    hash = "sha256-K4VbcnIFUjpmpfIuN38hFWXykx2MsN5E86bKoDzEtfM=";
  };
}
