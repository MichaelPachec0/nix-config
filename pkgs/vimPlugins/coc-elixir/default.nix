{ pkgs, ... }:
pkgs.vimUtils.buildVimPlugin rec {
  name = "coc-elixir";
  src = pkgs.fetchFromGitHub {
    owner = "elixir-lsp";
    repo = name;
    rev = "a48b9c8fd8651fc3886b16f5c2fc367d91f4cffc";
    sha256 = "xHCX3KWtA2+YrGRgua+vdI+8/yEJQjnZS0u82eHhuqw=";
  };
}
