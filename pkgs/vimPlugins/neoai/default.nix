{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  pname = "neoai.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "bryley";
    repo = "neoai.nvim";
    rev = "248c2001d0b24e58049eeb6884a79860923cfe13";
    hash = "sha256-haO7Qi2szWfTxWcknI7aJSKamQ/n6qIhIOxaO544IDY=";
  };
}
