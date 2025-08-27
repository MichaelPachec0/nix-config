{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config;
in {
  imports = [./coc.nix ./nvchad_b.nix];
  options = {
  };
  config = let
    inherit (config.programs.nixneovim) nvchad;
  in
    lib.mkMerge [
      (
        lib.mkIf nvchad.enable {
          # neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (old: {
          #   lua = old.lua.override {
          #     packageOverrides = final': prev': {
          #       neotest = prev'.neotest.overrideAttrs (oa: {
          #         doCheck = false;
          #       });
          #     };
          #   };
          # });
          programs.nixneovim = let
            # pkg = pkgs.neovim;
            # unwrapped = pkgs.neovim.neovim-unwrapped;
          in {
            enable = true;
            # package = inputs.neovim.packages.${pkgs.system}.default;
            # package = pkgs.master.neovim-unwrapped;
            # package = pkgs.neovim-nightly;
            package = pkgs.neovim-unwrapped;

            # enable = false;

            # WARN: this avoids the failing tests when packaging neovim plugins
            # TODO: CHECK WHEN THIS GETS FIXED IN NEOTEST AND NIXPKGS
            # https://github.com/nvim-neotest/neotest/issues/530
            # package = pkgs.master.neovim-unwrapped.overrideAttrs {
            #   lua = pkgs.lua.override {
            #     packageOverrides = final': prev': {
            #       neotest = prev'.neotest.overrideAttrs (oa: {
            #         doCheck = false;
            #       });
            #     };
            #   };
            # };
            defaultEditor = true;
            vimAlias = true;
            viAlias = true;
            globals = {
              mapleader = " ";
              # code_action_menu_show_details = true;
              # code_action_menu_show_diff = true;
              # code_action_menu_action_kind = true;
            };
            mappings = let
              tabConfig = {
                silent = true;
                expr = true;
                noremap = true;
                replace_keycodes = false;
              };
            in {
              # TODO: remaps
              # leader + [ ] switch windows?
              # leader + { } ( shift + [ ]) switch tabs
              # leader + | hsplit
              # leader + - vsplit
              # leader +
              # normalVisualOp." " = ''"<Nop>"'';
              # normalVisualOp."<leader>y" = ''"\"+y"'';
              # normalVisualOp."<leader>p" = ''"\"+p"'';
              # insert."jk" = ''"<esc>"'';
              # Telescope Keymaps
              # normalVisualOp."<leader>tff" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope find_files<CR>"'';
              # };
              # TODO: (high prio) for some reason, undo bugs out when calling
              # using the a keymap, but not when called directly.
              # NOTE: This does not seem to be caused by setting the keymap.
              # The chances of this occuring are higher the longer the nvim
              # instance is alive for.
              # normalVisualOp."<leader>fu" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope undo<CR>"'';
              # };
              # normalVisualOp."<leader>trg" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope live_grep<CR>"'';
              # };
              # normalVisualOp."<leader>tbf" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope buffers<CR>"'';
              # };
              # NOTE: moved from doing tht since Telescope themes is by
              # default <leader>th
              # normalVisualOp."<leader>ht" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope help_tags<CR>"'';
              # };
              # normalVisualOp."<leader>tgf" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope git_files<CR>"'';
              # };
              # normalVisualOp."<leader>tgc" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope git_commits<CR>"'';
              # };
              # normalVisualOp."<leader>tgb" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope git_branches<CR>"'';
              # };
              # normalVisualOp."<leader>tgbc" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope git_bcommits<CR>"'';
              # };
              # normalVisualOp."<leader>tgs" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope git_status<CR>"'';
              # };
              # normalVisualOp."<leader>tcm" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope commands<CR>"'';
              # };
              # normalVisualOp."<leader>tfb" = {
              #   noremap = true;
              #   action = ''"<CMD>Telescope file_browser<CR>"'';
              # };
              # # Window Maps
              # normalVisualOp."<leader>h" = {
              #   noremap = false;
              #   action = ''"<C-W>h"'';
              # };
              # normalVisualOp."<leader>j" = {
              #   noremap = true;
              #   action = ''"<C-W>j"'';
              # };
              # normalVisualOp."<leader>k" = {
              #   noremap = true;
              #   action = ''"<C-W>k"'';-nvim
              # };
              # normalVisualOp."<leader>l" = {
              #   noremap = true;
              #   action = ''"<C-W>l"'';
              # };
              # normalVisualOp."<leader><S-h>" = {
              #   noremap = true;
              #   action = ''"<C-W><S-h>"'';
              # };
              # normalVisualOp."<leader><S-j>" = {
              #   noremap = true;
              #   action = ''"<C-W><S-j>"'';
              # };
              # normalVisualOp."<leader><S-k>" = {
              #   noremap = true;
              #   action = ''"<C-W><S-k>"'';
              # };
              # normalVisualOp."<leader><S-l>" = {
              #   noremap = true;
              #   action = ''"<C-W><S-l>"'';
              # };
              # normalVisualOp."<leader>gph" = {
              #   action = ''"<Plug>(GitGutterPreviewHunk)"'';
              # };
              # normalVisualOp."<leader>guh" = {
              #   action = ''"<Plug>(GitGutterUndoHunk)"'';
              # };
              # normalVisualOp."<leader>gsh" = {
              #   action = ''"<Plug>(GitGutterStageHunk)"'';
              # };
              # normalVisualOp."<leader>ca" = {
              #   action = ''"<CMD>CodeActionMenu<CR>"'';
              # };
              # TAB mappings
              #        normal."<leader>[" = {
              #          silent = true;
              #          action = ''"<cmd>"'';
              #        };
            };
            # options = let
            #   tabSpaces = 2;
            # in {
            #   title = true;
            #   timeoutlen = 3000;
            #   updatetime = 300;
            #   signcolumn = "yes";
            #   smartindent = true;
            #   autoindent = true;
            #   number = true;
            #   laststatus = 2;
            #   showcmd = true;
            #   relativenumber = true;
            #   smartcase = true;
            #   showmodg = true;
            #   ruler = true;
            #   mouse = "a";
            #   filetype = "on";
            #   # set cursor in the middle
            #   # decide if space only formatting should be the norm.
            #   # expandtab = true;
            #   # this works here as well, which
            #   # shiftwidth = ${tabSpaces};
            #   # smarttab = true;
            #   # tabstop = ${tabSpaces};
            #   splitkeep = "screen";
            #   nofoldenable = true;
            # };
            # extraConfigLua = ''
            #   vim.opt.list = true
            #   vim.opt.listchars:append "space:⋅"
            #   vim.opt.listchars:append "eol:↴"
            #   vim.loader.enable()
            #   vim.cmd [[highlight IndentBlanklineContextSpaceChar guifg=#C68AEE gui=nocombine]]
            #   vim.cmd [[highlight IndentBlanklineContextChar guifg=#E06C75 gui=nocombine]]
            #   vim.cmd [[hi IndentBlanklineIndent1 guifg=#E06C75 gui=nocombine]]
            #   vim.cmd [[hi IndentBlanklineIndent2 guifg=#E5C07B gui=nocombine]]
            #   vim.cmd [[hi IndentBlanklineIndent3 guifg=#98C379 gui=nocombine]]
            #   vim.cmd [[hi IndentBlanklineIndent4 guifg=#56B6C2 gui=nocombine]]
            #   vim.cmd [[hi IndentBlanklineIndent5 guifg=#61AFEF gui=nocombine]]
            #   vim.cmd [[hi IndentBlanklineIndent6 guifg=#C678DD gui=nocombine]]
            #   vim.api.nvim_create_autocmd("ColorScheme", {
            #     desc = "Refresh indent colors",
            #     callback = function()
            #       vim.cmd [[highlight IndentBlanklineContextChar guifg=#E06C75 gui=nocombine]]
            #       vim.cmd [[hi IndentBlanklineIndent1 guifg=#E06C75 gui=nocombine]]
            #       vim.cmd [[hi IndentBlanklineIndent2 guifg=#E5C07B gui=nocombine]]
            #       vim.cmd [[hi IndentBlanklineIndent3 guifg=#98C379 gui=nocombine]]
            #       vim.cmd [[hi IndentBlanklineIndent4 guifg=#56B6C2 gui=nocombine]]
            #       vim.cmd [[hi IndentBlanklineIndent5 guifg=#61AFEF gui=nocombine]]
            #       vim.cmd [[hi IndentBlanklineIndent6 guifg=#C678DD gui=nocombine]]
            #   end,})
            #   vim.api.nvim_set_option_value("colorcolumn", "80", {})
            # '';
            # NOTE: Load nvchad and the custom init.lua files at the top
            # this also gives me a preInit.lua that can be loaded before
            # anything.
            # extraLuaPreConfig = ''
            #   dofile("${config.xdg.configHome}/nvim/lua/custom/preInit.lua")
            #   dofile("${pkgs.vimPlugins.nvchad}/init.lua")
            # '';
            # dofile("${config.xdg.configHome}/nvim/lua/custom/init.lua")
            nvchad.extraEarlyPlugins = with pkgs.vimPlugins; [
            ];
            nvchad.extraLazyPlugins = let
              plug = with pkgs.vimPlugins;
                [
                  fidget-nvim # for notifications
                  # Rust

                  # rust-tools-nvim # setup for rust-lsp and other tools (deprecated)
                  rustaceanvim # rust-tools sucessor
                  crates-nvim # rust
                  telescope-dap-nvim # debug view for telescope

                  # Lua/neovim lua stuff
                  neodev-nvim # testing
                  nvim-luadev

                  # nix
                  vim-nix # nix highlight
                  vim-nixhash

                  # Debug
                  nvim-dap # debug support
                  nvim-dap-ui # debug views for neovim
                  nvim-nio # for nvim-dap

                  lsp-format-nvim # TODO: how to use, this gets into conform or more generically none-ls/null-ls
                  nvim-dap-virtual-text # show debug info inline

                  # misc
                  telescope-undo-nvim # visualize undo actions
                  # TODO: (med prio) learn org mode.
                  orgmode # org mode in vim,
                  # nvim-lspconfig # sane defaults for lsp's
                  telescope-media-files-nvim
                  telescope-github-nvim
                  telescope-cheat-nvim # for tldr in the neovim
                  # (telescope-cheat-nvim.overrideAttrs (old: {
                  #   src = ../../../forked/telescope-cheat.nvim;
                  #   }))
                  telescope-manix # nixpkgs docs search in telescope
                  hop-nvim # semantic cursor pointing TODO: learn how to use
                  hydra-nvim
                  telescope-fzf-writer-nvim # fzf in nvim
                  telescope-fzf-native-nvim # fzf in nvim
                  nui-nvim # floating windowing ui in nvim
                  neoconf-nvim
                  inc-rename-nvim # lsp rename
                  # vscode bar for nvim
                  barbecue-nvim
                  lspsaga-nvim # lsp helper plugin
                  nvim-navic # for the
                  nvim-web-devicons
                  # WARN: This is nixneovim pkgs
                  dropbar-nvim

                  # TODO: (med prio) are the below plugins needed?
                  telescope-ui-select-nvim # ui select support for telescope

                  sqlite-lua # dependcy for
                  nvim-treesitter-context # shows location in program structure
                  # nvim-code-action-menu # pop code actions
                  actions-preview-nvim # ^ alternative
                  dressing-nvim # makes it possible to draw ui elements on top
                  # of buffers ie LSP rename
                  trouble-nvim # Colorful diagnostics/lsp/telescope
                  todo-comments-nvim # colorful todo comments
                  nvim-lightbulb # show lightbulb hints when line is actionable
                  lsp-inlayhints-nvim # self-explanatory
                  vim-wakatime # time-tracker
                  null-ls-nvim # code action/lint/diagnostics configurator.

                  # TODO: (low prio) learn.
                  harpoon # mark files for later use

                  # TODO: (med prio) learn.
                  vim-visual-multi # multi cursor
                  # ai
                  ChatGPT-nvim
                  windsurf-vim
                  # rename from above: 2025-04-09
                  # codeium-vim
                  # sg-nvim this is deprecated

                  osv-nvim
                  # testing
                  neotest
                  neotest-rust
                  neotest-python
                  neotest-plenary
                  neotest-go
                  neotest-elixir
                  neotest-dart
                  neotest-deno
                  neotest-haskell
                  neotest-elixir
                  neotest-gtest

                  elixir-tools-nvim
                  clangd_extensions-nvim
                  telescope-file-browser-nvim
                  telescope-project-nvim
                  telescope-live-grep-args-nvim
                  telescope-frecency-nvim

                  # TODO: plugins that i need more time to implement in my
                  # workflow.
                  yankring # synchronize yank deleted between different instances of vim
                  windows-nvim # enables auto resizing of windows, might or might enable
                  lazygit-nvim
                  git-nvim
                  ts-software-licenses-nvim
                  minimap-vim
                  cmp-tabnine
                  none-ls-extras-nvim
                  # obsidian-nvim
                ]
                # ++ (with pkgs.stable.vimPlugins; [
                #   neotest
                #   neotest-rust
                #   neotest-python
                #   neotest-plenary
                #   neotest-go
                #   neotest-elixir
                #   neotest-dart
                #   neotest-deno
                #   neotest-haskell
                #   neotest-elixir
                # ])
                ++ (with pkgs.vimExtraPlugins; [
                  # vlog-nvim
                ])
                ++ (with pkgs.vimPlugins; [
                  # Custom plugins, these are not included in nixpkgs
                  stay-centered # keeps cursor centered whenever possible
                  virt-column # show char on colorcolum.
                  vimBeGood # game inside vim to practice motions
                  indentmini # show indentations using nvim decoration api
                  wtf-nvim
                  nvim-dap-repl-highlights
                  neoai-nvim
                  telescope-docker-nvim
                  nvim-emmet
                  kitty-scrollback-nvim
                  clear-action-nvim
                  # none-ls-nvim
                  (
                    pkgs.vimUtils.buildVimPlugin {
                      pname = "none-ls.nvim";
                      version = "2025-02-24";
                      src = inputs.none-ls;
                    }
                  )
                  inlay-hints-nvim
                  guihua-lua
                  pfp-vim
                  cspell-nvim
                  render-markdown-nvim
                ])
                ++ (with pkgs.stable.vimPlugins; [])
                ++ (with pkgs.master.vimPlugins; [
                  typescript-tools-nvim
                  godbolt-nvim
                  # go-nvim

                  (pkgs.master.vimPlugins.go-nvim.overrideAttrs (
                    old: {
                      # _GO_NVIM_CFG = 1;
                      checkInputs =
                        (with pkgs; [
                          guihua-lua
                          nvim-lspconfig
                        ])
                        ++ old.checkInputs;
                      doCheck = false;
                      # dependencies =
                      #   (with pkgs; [
                      #     # guihua-lua
                      #     # nvim-lspconfig
                      #   ])
                      #   ++ old.dependencies;
                      # doCheck = false;
                      # TODO: FIND OUT WHY THIS NEEDS FIXING
                      nvimSkipModules = [
                        # "go.ts.utils"
                        # "go.fixplurals"
                        # "guihua.ts_obsolete"
                      ];
                    }
                  ))
                ]);
            in
              [];
              # plug;
          };

          # TODO: change to using vscode's package setup, this way there is less boilerplate written
          # home = let ext = ".vscode/extensions/";
          # mkExt = {  source,  enable ? true, recursive ?  true }: {
          #     inherit source enable recursive;
          #   };
          # in {
          #   packages = with pkgs; [
          #   patchelf
          #   file
          #   ];
          #  file."${ext}/vadimcn.vscode-lldb/" = mkExt {
          #     source = "${pkgs.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb";
          #   };
          #   file."${ext}/pylance/" = mkExt { source = "${pkgs.vscode-extensions.ms-python.vscode-pylance}/share/vscode/extensions/MS-python.vscode-pylance/";
          #   };
          #   };

          xdg.configFile."cspell/cspell.json".text = let
            dict = "${inputs.cspell-dicts}/dictionaries";
          in
            builtins.toJSON {
              allowCompoundWords = true;
              import = [
                "${dict}/bash/cspell-ext.json"
                # "${dict}/clojure/cspell-ext.json"
                "${dict}/cpp/cspell-ext.json"
                # "${dict}/csharp/cspell-ext.json"
                "${dict}/css/cspell-ext.json"
                # "${dict}/dart/cspell-ext.json"
                "${dict}/django/cspell-ext.json"
                "${dict}/docker/cspell-ext.json"
                # "${dict}/dotnet/cspell-ext.json"
                "${dict}/elixir/cspell-ext.json"
                # "${dict}/en_US/cspell-ext.json"
                # "${dict}/filetypes/cspell-ext.json"
                # "${dict}/fsharp/cspell-ext.json"
                "${dict}/git/cspell-ext.json"
                "${dict}/golang/cspell-ext.json"
                # "${dict}/haskell/cspell-ext.json"
                "${dict}/html-symbol-entities/cspell-ext.json"
                "${dict}/html/cspell-ext.json"
                "${dict}/k8s/cspell-ext.json"
                # "${dict}/kotlin/cspell-ext.json"
                "${dict}/makefile/cspell-ext.json"
                "${dict}/markdown/cspell-ext.json"
                "${dict}/node/cspell-ext.json"
                "${dict}/npm/cspell-ext.json"
                "${dict}/python/cspell-ext.json"
                "${dict}/data-science/cspell-ext.json"
                # "${dict}/ruby/cspell-ext.json"
                "${dict}/rust/cspell-ext.json"
                # "${dict}/scala/cspell-ext.json"
                "${dict}/shell/cspell-ext.json"
                "${dict}/sql/cspell-ext.json"
                # "${dict}/svelte/cspell-ext.json"
                "${dict}/swift/cspell-ext.json"
                # "${dict}/vue/cspell-ext.json"
                "${dict}/lua/cspell-ext.json"
                "${dict}/typescript/cspell-ext.json"
                "${dict}/vim/cspell-ext.json"
                "${dict}/java/cspell-ext.json"
              ];
              dictionaries = ["user"];
              dictionaryDefinitions = [
                {
                  name = "user";
                  path = "~/.local/share/cspell/user.txt";
                  description = "User defined words";
                }
              ];
              languageSettings = [
                {
                  languageId = "lua,fnl";
                  locale = "*";
                  ignoreRegExpList = ["/require.*/"];
                  dictionaries = ["lua"];
                }
                {
                  languageId = "vim";
                  locale = "*";
                  ignoreRegExpList = ["/Plug .*/"];
                  dictionaries = ["vim"];
                }
              ];
              overrides = [
                {
                  filename = "**/{*.fnl}";
                  languageId = "fnl";
                }
              ];
            };
        }
      )
      # (lib.mkIf (!nvchad.enable) {
      #   programs.nixneovim = {
      #     enable = true;
      #     defaultEditor = true;
      #     viAlias = true;
      #     vimAlias = true;
      #     # might change this to a more updated neovim
      #     # package = pkgs.neovim-unwrapped;
      #     colorschemes = {
      #       gruvbox-material = {
      #         enable = true;
      #         enableBold = true;
      #         background = "hard";
      #         #betterPerformance = true;
      #         #dimInactiveWindows = true;
      #         # TODO: fill in
      #         extraConfig = {};
      #         extraLua = {
      #           post = "";
      #           pre = "";
      #         };
      #         foreground = "material";
      #         #transparentBackground = 2;
      #       };
      #     };
      #     extraConfigLua = ''
      #       do
      #         require("stay-centered").setup()
      #       end
      #       do
      #         require("indentmini").setup({ char = "⋅", })
      #         vim.cmd.highlight("default link IndentLine Comment")
      #       end
      #         local keyset = vim.keymap.set
      #         -- Autocomplete
      #       do
      #         function _G.check_back_space()
      #           local col = vim.fn.col('.') - 1
      #           return col == 0 or vim.fn.getline('.'):sub(col,col):match('%s') ~= nil
      #         end
      #       end
      #       do
      #         function _G.show_docs()
      #           local cw = vim.fn.expand('<cword>')
      #           if vim.fn.index({'vim','help'}, vim.bo.filetype) >= 0 then
      #             vim.api.nvim_command('h ' .. cw)
      #           elseif vim.api.nvim_eval('coc#rpc#ready()') then
      #               vim.fn.CocActionAsync('doHover')
      #           else
      #             vim.api.nvim_command('!' .. vim.o.keywordprg .. ' ' .. cw)
      #           end
      #         end
      #       end
      #       do
      #         require("telescope").load_extension "file_browser"
      #         require("telescope").load_extension "undo"
      #       end
      #     '';
      #     extraConfigVim = "";
      #     extraLuaPostConfig = "";
      #     extraPackages = [];
      #     extraPlugins = let
      #       vp = pkgs.vimPlugins;
      #       np = pkgs.nodePackages_latest;
      #     in
      #       [
      #         vp.coc-elixir
      #         vp.stay-centered
      #         vp.coc-tailwindcss
      #         vp.coc-css
      #         vp.coc-vetur
      #         vp.coc-tsserver
      #         vp.coc-tslint-plugin
      #         vp.coc-docker
      #         vp.coc-lua
      #         vp.coc-sh
      #         vp.coc-lightbulb
      #         vp.indentmini
      #         vp.coc-prettier
      #         vp.coc-html
      #         #vp.rust-vim
      #         vp.coc-go
      #         vp.vim-nix
      #         vp.vim-nixhash
      #         vp.yankring
      #         vp.windows-nvim
      #         vp.vim-toml
      #         #vp.coc-rust-analyzer
      #         vp.fzf-vim
      #         vp.vim-devicons
      #         vp.coc-git
      #         vp.vim-gitgutter
      #         vp.lazygit-nvim
      #         vp.vimBeGood
      #         vp.vim-cool
      #         vp.telescope-file-browser-nvim
      #         vp.telescope-undo-nvim
      #         vp.nvim-web-devicons
      #         #vp.coc-json
      #         #vp.coc-yaml
      #         #vp.coc-html
      #         #vp.coc-pyright
      #         {
      #           plugin = vp.vim-ccls;
      #           config = ''
      #             let g:ccls_close_on_jump = v:true
      #             let g:ccls_level = 5
      #           '';
      #         }
      #       ]
      #       ++ [];
      #     globals = {
      #       mapleader = " ";
      #       code_action_menu_show_details = true;
      #       code_action_menu_show_diff = true;
      #       code_action_menu_action_kind = true;
      #     };
      #     mappings = let
      #       tabConfig = {
      #         silent = true;
      #         expr = true;
      #         noremap = true;
      #         replace_keycodes = false;
      #       };
      #     in {
      #       normalVisualOp." " = ''"<Nop>"'';
      #       normalVisualOp."<leader>y" = ''"\"+y"'';
      #       normalVisualOp."<leader>p" = ''"\"+p"'';
      #       insert."jk" = ''"<esc>"'';
      #       ## CoC config
      #       # This changes the use of tab for code completion purposes
      #       insert."<TAB>" =
      #         {
      #           action = ''
      #             "coc#pum#visible() ? coc#pum#next(1) : v:lua.check_back_space() ? '<Tab>' : coc#refresh()"'';
      #           desc = "Use tab to select tab completions in coc.";
      #         }
      #         // tabConfig;
      #       # This does the same for shift + tab but in the opposite direction
      #       insert."<S-TAB>" =
      #         {
      #           action = ''
      #             "coc#pum#visible() ? coc#pum#prev(1) : '<C-h>'"
      #           '';
      #           desc = "Use Shift-tab to choose the previous completion in coc.";
      #         }
      #         // tabConfig;
      #       # Pressing enter will autocomplete the result, the action make sure that the there is coc popup use
      #       insert."<CR>" = {
      #         silent = true;
      #         expr = true;
      #         noremap = true;
      #         action = ''
      #           "coc#pum#visible() ? coc#pum#confirm() : '<C-G>u<CR><C-R>=coc#on_enter()<CR>'"
      #         '';
      #         desc = "When selecting a autocompletion, enter inserts it.";
      #       };
      #       normal."<leader>rn" = {
      #         action = ''
      #           "<Plug>(coc-rename)"
      #         '';
      #       };
      #       normal."gd" = {
      #         silent = true;
      #         action = ''"<Plug>(coc-definition)"'';
      #       };
      #       normal."K" = {
      #         silent = true;
      #         noremap = false;
      #         action = ''"<CMD>lua _G.show_docs()<CR>"'';
      #       };
      #       normalVisualOp."<leader>cpf" = {
      #         noremap = true;
      #         action = ''":CocCommand prettier.formatFile<CR>"'';
      #       };
      #       normalVisualOp."<leader>crf" = {
      #         silent = true;
      #         noremap = true;
      #         action = ''"coc#refresh()"'';
      #       };
      #       normalVisualOp."<leader>fff" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope find_files<CR>"'';
      #       };
      #       normalVisualOp."<leader>frg" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope live_grep<CR>"'';
      #       };
      #       normalVisualOp."<leader>fbf" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope buffers<CR>"'';
      #       };
      #       normalVisualOp."<leader>fht" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope help_tags<CR>"'';
      #       };
      #       normalVisualOp."<leader>fgf" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope git_files<CR>"'';
      #       };
      #       normalVisualOp."<leader>fgc" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope git_commits<CR>"'';
      #       };
      #       normalVisualOp."<leader>fgb" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope git_branches<CR>"'';
      #       };
      #       normalVisualOp."<leader>fgs" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope git_status<CR>"'';
      #       };
      #       normalVisualOp."<leader>fcm" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope commands<CR>"'';
      #       };
      #       normalVisualOp."<leader>ffb" = {
      #         noremap = true;
      #         action = ''"<CMD>Telescope file_browser<CR>"'';
      #       };
      #       normalVisualOp."<leader>h" = {
      #         noremap = true;
      #         action = ''"<C-W>h"'';
      #       };
      #       normalVisualOp."<leader>j" = {
      #         noremap = true;
      #         action = ''"<C-W>j"'';
      #       };
      #       normalVisualOp."<leader>k" = {
      #         noremap = true;
      #         action = ''"<C-W>k"'';
      #       };
      #       normalVisualOp."<leader>l" = {
      #         noremap = true;
      #         action = ''"<C-W>l"'';
      #       };
      #       normalVisualOp."<leader><S-h>" = {
      #         noremap = true;
      #         action = ''"<C-W><S-h>"'';
      #       };
      #       normalVisualOp."<leader><S-j>" = {
      #         noremap = true;
      #         action = ''"<C-W><S-j>"'';
      #       };
      #       normalVisualOp."<leader><S-k>" = {
      #         noremap = true;
      #         action = ''"<C-W><S-k>"'';
      #       };
      #       normalVisualOp."<leader><S-l>" = {
      #         noremap = true;
      #         action = ''"<C-W><S-l>"'';
      #       };
      #       normalVisualOp."<leader>gph" = {
      #         action = ''"<Plug>(GitGutterPreviewHunk)"'';
      #       };
      #       normalVisualOp."<leader>guh" = {
      #         action = ''"<Plug>(GitGutterUndoHunk)"'';
      #       };
      #       normalVisualOp."<leader>gsh" = {
      #         action = ''"<Plug>(GitGutterStageHunk)"'';
      #       };
      #
      #       #        normal."<leader>[" = {
      #       #          silent = true;
      #       #          action = ''"<cmd>"'';
      #       #        };
      #     };
      #     options = let
      #       tabSpaces = 2;
      #     in {
      #       timeoutlen = 3000;
      #       updatetime = 300;
      #       signcolumn = "yes";
      #       smartindent = true;
      #       autoindent = true;
      #       number = true;
      #       laststatus = 2;
      #       showcmd = true;
      #       relativenumber = true;
      #       smartcase = true;
      #       showmode = true;
      #       ruler = true;
      #       mouse = "a";
      #       filetype = "on";
      #       # set cursor in the middle
      #       # decide if space only formatting should be the norm.
      #       # expandtab = true;
      #       # this works here as well, which
      #       # shiftwidth = ${tabSpaces};
      #       # smarttab = true;
      #       # tabstop = ${tabSpaces};
      #       splitkeep = "screen";
      #       nofoldenable = true;
      #     };
      #     plugins = {
      #       airline = {
      #         enable = true;
      #         powerline = true;
      #         theme = "base16_gruvbox_dark_hard";
      #       };
      #       telescope = {
      #         enable = true;
      #         extensions = {
      #           manix = {enable = true;};
      #           mediaFiles = {enable = true;};
      #         };
      #       };
      #       todo-comments = {enable = true;};
      #       treesitter = {
      #         enable = true;
      #         folding = true;
      #         indent = false;
      #         installAllGrammars = true;
      #         refactor = {
      #           highlightCurrentScope.enable = true;
      #           highlightDefinitions.enable = true;
      #           smartRename.enable = true;
      #         };
      #         incrementalSelection = {enable = true;};
      #         extraLua = {
      #           pre = ''
      #             local vim = vim
      #             local api = vim.api
      #             local M = {}
      #             -- function to create a list of commands and convert them to autocommands
      #             -------- This function is taken from https://github.com/norcalli/nvim_utils
      #             vim.cmd("autocmd BufWinEnter * silent! :%foldopen!")
      #           '';
      #           post = "";
      #         };
      #       };
      #       treesitter-context = {enable = true;};
      #       # TODO: look at docs: https://github.com/folke/trouble.nvim#%EF%B8%8F-configuration
      #       trouble = {enable = true;};
      #       ts-context-commentstring = {enable = true;};
      #       # TODO: research options https://nixneovim.github.io/NixNeovim/options.html#opt-programs.nixneovim.plugins.undotree.enable
      #       # TODO: docs here: https://github.com/mbbill/undotree/#usage
      #       undotree = {enable = true;};
      #       vim-easy-align = {enable = true;};
      #     };
      #   };
      # })
    ];
}
