{pkgs, ...}: let
  v = pkgs.vimUtils;
  p = pkgs.vimPlugins;
in
  v.buildVimPlugin rec {
    pname = "guihua.lua";
    version = "2024-01-25-master";
    src = pkgs.fetchFromGitHub {
      owner = "ray-x";
      repo = "${pname}";
      rev = "ef44ba40f12e56c1c9fa45967f2b4d142e4b97a0";
      hash = "sha256-9iFqh12orsGnQniDloO+aXoBYuTqOW4pGHi3LBB2m4Q=";
      # rev = "9fb6795474918b492d9ab01b1ebaf85e8bf6fe0b";
      # hash = "sha256-0fpcYEdWfpy8MatH8cjalGOQ7/tau6ciiuSV1t09BlY=";
    };
    buildPhase = ''
      (
        cd lua/fzy
        make
      )
    '';
    # TODO: maybe fix this? i could care less
    # dont understand what require(".init") does
    # 2025-12-31: nvimSkipModule has been renamed to nvimSkipModules
    nvimSkipModules = [
      "fzy.fzy-lua-native"
    ];

    dependencies = with p; [
      plenary-nvim
      nvim-treesitter
      # nvim-treesitter-legacy
    ];
  }
