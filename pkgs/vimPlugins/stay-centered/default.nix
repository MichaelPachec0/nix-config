{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "stay-centered.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "arnamak";
    repo = pname;
    rev = "0715638e7110362f95ead35c290fcd040c2d2735";
    sha256 = "iaaWmXtgTPr3zecWD94D5PVB1yanpEb+oH4R2ukTT+A=";
  };
}
