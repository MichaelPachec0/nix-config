
{pkgs, inputs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "none-ls.nvim";
  version = "2024-03-01";
  src = inputs.none-ls;
}
