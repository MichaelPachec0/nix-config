# TODO: remaps
# leader + [ ] switch windows?
# leader + { } ( shift + [ ]) switch tabs
# leader + | hsplit
# leader + - vsplit
# leader +
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./coc.nix];
  options = {
    devMachine.enable =
      lib.mkEnableOption
      "Enables developer configuration. This includes certain packages as well as configuration.";
  };
  config = {
    home.packages = with pkgs;
      []
      ++ lib.optionals config.devMachine.enable [
        # nix
        unstable.nil
        # go
        gopls
        # c
        ccls
        # rust
        rust-analyzer
        #python
        black
        nodePackages.pyright
        # vscode-extensions.ms-python.vscode-pylance
        lazygit

      ];

    programs.neovim = {
      enable = true;
      plugins = with pkgs.vimPlugins;
        [
          vim-sensible
          vim-cool
        ]
        ++ lib.optionals config.devMachine.enable [
          rust-vim
          nvim-treesitter.withAllGrammars
          coc-go
          vim-ccls
          vim-nix
          vim-nixhash
          yankring
          windows-nvim
          vim-toml
          #coc-rust-analyzer
          fzf-vim
          vim-devicons
          coc-git
          vim-gitgutter
          lazygit-nvim
          vimBeGood
          #coc-json
          #coc-yaml
          #coc-html
          #coc-pyright
          {
            plugin = vim-ccls;
            config = ''
              let g:ccls_close_on_jump = v:true
              let g:ccls_level = 5
            '';
          }
          #coc-tsserver
        ];
      defaultEditor = true;
      vimdiffAlias = true;
      vimAlias = true;
      viAlias = true;
      withPython3 = true;
      withNodeJs = true;
      extraLuaConfig = ''
        vim.opt.nu = true
        vim.opt.relativenumber = true
        vim.opt.smartindent = true
        vim.opt.syntax = on 
        vim.opt.laststatus = 2
        vim.opt.showcmd = true
        vim.opt.showmode = true
        vim.opt.ruler = true
        vim.opt.autoindent = true
      '';

      #      extraConfig = ''
      #        set nocompatible ruler laststatus=2 showcmd showmode number relativenumber
      #        syntax on
      #        set smartindent
      #        set autoindent
      #
      #      '';
    };
  };
}
