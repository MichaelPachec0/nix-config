{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  pname = "git.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "dinhhuy258";
    repo = "git.nvim";
    rev = "6b4a66f8a66e567bf27a0ef1de72cf5e338df4c3";
    hash = "sha256-KKId09RIs8NNQHgrdnIGfosv9Po5tVxRXqwvyH5ELB4=";
  };
}
