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
              command = "${lib.getExe pkgs.unstable.nil}";
              filetypes = [ "nix" ];
              rootPatterns = [ "flake.nix" ];
              settings = {
                nil = {
                  formatting = {
                    command = [ "${lib.getExe pkgs.nixpkgs-fmt}" ];
                  };
                };
                binary = "/run/current-system/sw/bin/nix";
              };
            };
            gopls = {
              command = "${lib.getExe pkgs.gopls}";
              filetypes = [ "go" ];
              rootPatterns = [ "go.work" "go.mod" ".vim/" ".git/" ];
              initalizationOptions = { usePlaceholders = true; };
            };
            ccls = {
              command = "${lib.getExe pkgs.ccls}";
              filetypes = [ "c" "cpp" "objc" "objcpp" "cuda" ];
              rootPatterns =
                [ "compile_commands.json" ".ccls" ".git" ".ccls-root" ];
              initializationOptions = {
                cache = { directory = ".ccls-cache"; };
                client = { snippetSupport = true; };
              };
            };
            rust-analyzer = {
              command = "${lib.getExe pkgs.rust-analyzer}";
              filetypes = [ "rust" ];
              rootPatters = [ "Cargo.toml" ];
            };
            pylance = {
              enable = true;
              filetypes = [ "python" ];
              env = {
                ELECTRON_RUN_AS_NODE = 1;
                VSCODE_NLS_CONFIG = { locale = "en"; };
              };
              module =
                "${pkgs.vscode-extensions.ms-python.vscode-pylance}/share/vscode/extensions/MS-python.vscode-pylance/dist/server.bundle.js";
              initalizationOptions = { };
              settings = {
                python = {
                  languageserver = "Pylance";
                  analysis = {
                    typeCheckingMode = "strict";
                    diagnosticMode = "openFilesOnly";
                    stubPath = "./typings";
                    autoSearchPaths = true;
                    extraPaths = [ ];
                    diagnosticSeverityOverrides = { };
                    useLibraryCodeForTypes = true;
                    autoImportCompletions = true;
                    completeFunctionParens = true;
                    variableTypes = true;
                    functionReturnTypes = true;
                    inlayHints.pytestParameters = true;
                    enablePytestSupport = true;
                    autoFormatStrings = true;
                  };
                };
              };
            };
          };
        };
      };
    });
  };
}
