{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  pname = "sg.nvim";
  version = "0.2.3-pre";
  src = pkgs.fetchFromGitHub {
    owner = "sourcegraph";
    repo = "sg.nvim";
    rev = "a6a677225bffd66bc98e03ed77438cde93a6fd31";
    hash = "sha256-4tMG8oNwT3XstSpxqs4J5i2KwbgEs9GdZ9P2cb5oIJA=";
  };
  dependencies = with pkgs.vimPlugins; [plenary-nvim];
}
