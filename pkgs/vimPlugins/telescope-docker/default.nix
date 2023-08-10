{pkgs, ...}:
pkgs.vimUtils.buildVimPluginFrom2Nix rec {
  pname = "telescope-docker.nvim";
  version = "2023-09-28";
  src = pkgs.fetchFromGitHub {
    owner = "lpoto";
    repo = pname;
    rev = "4219840291d9e3e64f6b8eefa11e8deb14357581";
    hash = "sha256-nOMPWVlQR4jRdIt7UDADxl1p3lkx7+fVVboF/6wZW1g=";
  };
}
