# chip telescope-software-licenses.nvim
{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  pname = "telescope-software-licenses.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "chip";
    repo = "telescope-software-licenses.nvim";
    rev = "fb5fc33b6afc994756e2f372423c365bf66f2256";
    hash = "sha256-luyCjkZSm1F6qoRpP5hHRAx4632u6JFuX2s7m2s8y60=";
  };
}
