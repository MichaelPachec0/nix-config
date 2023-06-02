{ config, lib, pkgs, ... }: {
  options = {
    devMachine.enable = lib.mkEnableOption
      "Enables developer configuration. This includes certain packages as well as configuration.";
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
        lazygit

      ];

    programs.neovim = lib.attrsets.recursiveUpdate {
      enable = true;
      plugins = with pkgs.vimPlugins;
        [
          vim-sensible
          vim-cool

        ] ++ lib.optionals (config.devMachine.enable) [
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
    } (lib.attrsets.optionalAttrs (config.devMachine.enable) {
      coc = {
        enable = true;
        settings = {
          semanticTokens = { filetypes = [ ]; };
          coc.preferences.formatOnSaveFiletypes = [ "nix" ];
          languageserver = {
            # need to enable other language servers, like js, rust, go, elixir, c? c++ 
            nix = {
              command = "${lib.getExe pkgs.unstable.nil}";
              filetypes = [ "nix" ];
              rootPatterns = [ "flake.nix" ];
              settings = {
                nil = {
                  formatting = { command = [ "${lib.getExe pkgs.nixfmt}" ]; };
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
              rootPatterns = [
                "Pipfile"
                "requirements.txt"
                "setup.py"
                "setup.cfg"
                "pyrightconfig.json"
                "pyrproject.toml"
              ];
              module =
                "${pkgs.vscode-extensions.ms-python.vscode-pylance}/share/vscode/extensions/MS-python.vscode-pylance/dist/server.bundle.js";
              initalizationOptions = { };
              settings = {
                telemetry.telemetryLevel = "off";
                python = {
                  languageserver = "Pylance";
                  analysis = {
                    typeCheckingMode = "strict";
                    diagnosticMode = "workspace";
                    stubPath = "./typings";
                    autoSearchPaths = true;
                    extraPaths = [ ];
                    diagnosticSeverityOverrides = { };
                    useLibraryCodeForTypes = true;
                    autoImportCompletions = true;
                    completeFunctionParens = true;
                    variableTypes = true;
                    functionReturnTypes = true;
                    enablePytestSupport = true;
                    autoFormatStrings = true;
                    inlayHints = {
                      variableTypes = true;
                      functionReturnTypes = true;
                      pytestParameters = true;
                    };
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
