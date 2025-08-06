{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "clear-action.nvim";
  version = "2024-01-20";
  src = 
  pkgs.fetchFromGitHub {
    owner = "luckasRanarison";
    repo = "${pname}";
    rev = "29ca65333238607ff503950fdd5d122d73a3902f";
    hash = "sha256-RJHNwvEOSW4JpRPRGiMb9tssGV4E3Jf0dS5jzVAWjRA=";
  };
}
