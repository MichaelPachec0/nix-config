{pkgs, ...}: let
  v = pkgs.vimUtils;
  p = pkgs.vimPlugins;
in
  v.buildVimPlugin rec {
    pname = "cspell.nvim";
    version = "2024-11-09-master";
    src = pkgs.fetchFromGitHub {
      owner = "davidmh";
      repo = pname;
      rev = "2c29bf573292c8f5053383d1be4ab908f4ecfc47";
      hash = "sha256-t0wicweW/jFQ4A1gRL5PgQMnfasc2QDjJ7ABih4KpH0=";
    };
    dependencies = with p; [
      plenary-nvim
      null-ls-nvim
    ];
  }
