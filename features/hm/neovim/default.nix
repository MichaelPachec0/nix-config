{ config, lib, pkgs, ... }: {
  options = {
    devMachine.enable = lib.mkEnableOption "Enables lsp's for neovim.";
  };
  config = {
    home.packages = with pkgs;
      [ ] ++ lib.optionals (config.devMachine.enable) [
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
        vscode-extensions.ms-python.vscode-pylance

      ];

    programs.neovim = lib.attrsets.recursiveUpdate {
      enable = true;
      plugins = with pkgs.vimPlugins;
        [

        ] ++ lib.optionals (config.devMachine.enable) [
          rust-vim
          coc-go
          vim-ccls
          vim-nix
          vim-nixhash
          yankring
          windows-nvim
          vim-toml
          coc-rust-analyzer
          vim-sensible
          fzf-vim
          vim-devicons
          coc-git
          coc-json
          coc-yaml
          coc-html
          coc-pyright
          coc-clangd
          coc-tsserver
        ];
      defaultEditor = true;
      vimdiffAlias = true;
      vimAlias = true;
      viAlias = true;
      withPython3 = true;
      withNodeJs = true;
      extraConfig = ''
        set nocompatible ruler laststatus=2 showcmd showmode number 
        syntax on
        set smartindent
        set autoindent
      '';
    } (lib.attrsets.optionalAttrs (config.devMachine.enable) {
      coc = {
        enable = true;
        settings = {
          languageserver = {
            # need to enable other language servers, like js, rust, go, elixir, c? c++ 
            nix = {
              command = "nil";
              filetypes = [ "nix" ];
              rootPatterns = [ "flake.nix" ];
              settings = {
                nil = { formatting = { command = [ "nixpkgs-fmt" ]; }; };
              };
            };
            go = {
              command = "gopls";
              filetypes = [ "go" ];
              rootPatterns = [ "go.work" "go.mod" ".vim/" ".git/" ];
              initalizationOptions = { usePlaceholders = true; };
            };
            c = {
              command = "ccls";
              filetypes = [ "c" "cpp" "objc" "objcpp" "cuda" ];
              rootPatterns = [ "compile_commands.json" ".ccls" ".git" ];
              initializationOptions = {
                cache = { directory = ".ccls-cache"; };
                client = { snippetSupport = true; };
              };
            };
            rust-analyzer = { enable = true; };
            pylance = {
              enable = true;
              filetypes = [ "python" ];
              # "~/.vscode/extensions/ms-python.vscode-pylance-2020.7.3/server/server.bundle.js"
              module =
                "${pkgs.vscode-extensions.ms-python.vscode-pylance}/server/server.bundle.js";
              initalizationOptions = { };
              settings = {
                python.analysis = {
                  typeCheckingMode = "basic";
                  diagnosticMode = "openFilesOnly";
                  stubPath = "./typings";
                  autoSearchPaths = true;
                  extraPaths = [ ];
                  diagnosticSeverityOverrides = { };
                  useLibraryCodeForTypes = true;
                };
              };
            };
          };
        };
      };
    });
  };
}
