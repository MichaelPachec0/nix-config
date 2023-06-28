{ pkgs, ... }:
pkgs.vimUtils.buildVimPlugin rec {
  name = "block";
  src = pkgs.fetchFromGitHub {
    owner = "HampusHauffman";
    repo = "${name}.nvim";
    rev = "26fc996788cfecf7c9ebc9ac42f2133094092822";
    sha256 = "i9ZvuaXRPu2duZkjH2y6Sxexf+BfmUdE3YHVKgG6Yz4=";
  };
}
