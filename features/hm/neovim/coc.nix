{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config;
in {
  config = {
    programs.neovim.coc = lib.mkIf cfg.devMachine.enable {
      # Since moving onto native lsp, disable coc
      # TODO: (very low prio) Make this configurable for the small chance that coc might be wanted.
      enable = false;
      settings = {
        mappings = let
          tabConfig = {
            silent = true;
            expr = true;
            noremap = true;
            # NOTE: This depends on codebits that for the moment are not in upstream.
            # TODO: (high prio) future PR.
            replace_keycodes = false;
          };
        in {
          # CoC configg
          # This changes the use of tab for code completion purposes
          insert."<TAB>" =
            {
              action = ''
                "coc#pum#visible() ? coc#pum#next(1) : v:lua.check_back_space() ? '<Tab>' : coc#refresh()"'';
              desc = "Use tab to select tab completions in coc.";
            }
            // tabConfig;
          # This does the same for shift + tab but in the opposite direction
          insert."<S-TAB>" =
            {
              action = ''
                "coc#pum#visible() ? coc#pum#prev(1) : '<C-h>'"
              '';
              desc = "Use Shift-tab to choose the previous completion in coc.";
            }
            // tabConfig;
          # Pressing enter will autocomplete the result, the action make sure that the there is coc popup use
          insert."<CR>" = {
            silent = true;
            expr = true;
            noremap = true;
            action = ''
              "coc#pum#visible() ? coc#pum#confirm() : '<C-G>u<CR><C-R>=coc#on_enter()<CR>'"
            '';
            desc = "When selecting a autocompletion, enter inserts it.";
          };
          normal."<leader>rn" = {
            action = ''
              "<Plug>(coc-rename)"
            '';
          };
          normal."gd" = {
            silent = true;
            action = ''"<Plug>(coc-definition)"'';
          };
          normal."K" = {
            silent = true;
            noremap = false;
            action = ''"<CMD>lua _G.show_docs()<CR>"'';
          };
          normalVisualOp."<leader>cpf" = {
            noremap = true;
            action = ''":CocCommand prettier.formatFile<CR>"'';
          };
          normalVisualOp."<leader>crf" = {
            silent = true;
            noremap = true;
            action = ''"coc#refresh()"'';
          };
        };
        semanticTokens = {filetypes = [];};
        coc.preferences.formatOnSaveFiletypes = ["nix"];
        languageserver = {
          # need to enable other language servers, like js, rust, go, elixir, c? c++
          nix = {
            # TODO: LSP will probably run on a dev machine with a wayland display. Since moving laptop (current dev machine) to unstable, this attrset is non-existant.
            command = "${lib.getExe pkgs.unstable.nil}";
            filetypes = ["nix"];
            rootPatterns = ["flake.nix"];
            settings = {
              nil = {
                formatting = {command = ["${lib.getExe pkgs.nixfmt}"];};
              };
              binary = "/run/current-system/sw/bin/nix";
            };
          };
          gopls = {
            command = "${lib.getExe pkgs.gopls}";
            filetypes = ["go"];
            rootPatterns = ["go.work" "go.mod" ".vim/" ".git/"];
            initalizationOptions = {usePlaceholders = true;};
          };
          ccls = {
            command = "${lib.getExe pkgs.ccls}";
            filetypes = ["c" "cpp" "objc" "objcpp" "cuda"];
            rootPatterns = ["compile_commands.json" ".ccls" ".git" ".ccls-root"];
            initializationOptions = {
              cache = {directory = ".ccls-cache";};
              client = {snippetSupport = true;};
            };
          };
          rust-analyzer = {
            command = "${lib.getExe pkgs.rust-analyzer}";
            filetypes = ["rust"];
            rootPatters = ["Cargo.toml"];
            settings = {
              rust-analyzer = {cargo = {features = ["all"];};};
            };
          };
          pylance = {
            enable = true;
            filetypes = ["python"];
            env = {
              ELECTRON_RUN_AS_NODE = 1;
              VSCODE_NLS_CONFIG = {locale = "en";};
            };
            rootPatterns = [
              "Pipfile"
              "requirements.txt"
              "setup.py"
              "setup.cfg"
              "pyrightconfig.json"
              "pyrproject.toml"
            ];
            module = "${pkgs.vscode-extensions.ms-python.vscode-pylance}/share/vscode/extensions/MS-python.vscode-pylance/dist/server.bundle.js";
            initalizationOptions = {};
            settings = {
              telemetry.telemetryLevel = "off";
              python = {
                languageserver = "Pylance";
                analysis = {
                  typeCheckingMode = "strict";
                  diagnosticMode = "workspace";
                  stubPath = "./typings";
                  autoSearchPaths = true;
                  extraPaths = [];
                  diagnosticSeverityOverrides = {};
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
          erlang = {
            command = "${lib.getExe pkgs.erlang-ls}";
            filetypes = ["erlang"];
          };
        };
      };
    };
  };
}
