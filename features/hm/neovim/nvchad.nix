# NOTE: M. This is code from https://github.com/azuwis/nix-config/blob/master/modules/common/nvchad/home.nix
# commit: 4fa924f741499f960a1a9ecfc8fe6c1108fa4d1c
# Includes certain changes, mainly extra comments and changes to use more custom config.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.nixneovim;
  v = pkgs.vimUtils;
  p = pkgs.vimPlugins;
  # inherit (pkgs) nvchad nvchad-ui base46;
  # TODO: (med prio) migrate from v2.0 to v2.5, there is some work that needs to be done here.
  # minimally these plugins and their patches will need to be revamped
  nvchad = pkgs.vimPlugins.nvchad.overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      inherit (old.src) owner repo;
      rev = "6f25b2739684389ca69ea8229386c098c566c408";
      hash = "sha256-w/ZRxWxuU/ECq3ntkXek5BgJiBcUCBOjrvNBc4U94V4=";
    };
    postPatch = ''
      # substituteInPlace lua/plugins/init.lua \
      substituteInPlace lua/nvchad/plugins/init.lua \
      --replace-fail '"L3MON4D3/LuaSnip"' '"L3MON4D3/luasnip"' \
      --replace-fail '"nvchad/ui",' '"nvchad/ui", name = "nvchad-ui",' \
      # These were removed
      # --replace '"numToStr/Comment.nvim"' '"numToStr/comment.nvim"' \
      # --replace '"NvChad/nvim-colorizer.lua"' '"catgoose/nvim-colorizer.lua"'

      # nvchad colorizer was moved to a new repo
      # hope and pray that nvchad-ui still works
    '';
  });
  nvchad-ui = pkgs.vimPlugins.nvchad-ui.overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      inherit (old.src) owner repo;
      rev = "adcc97d7c7b97d3527a31338615751d2503fe0a4";
      hash = "sha256-lwFWqJy0yR/wGOF3T2yO9ZiIuBTIGcWr06G0510G+/k=";
    };
    # this should still work
    patches = [
      ./ui.patch
    ];
  });
  base46 = pkgs.vimPlugins.base46.overrideAttrs (old: {
    version = "2025-01-17-master";
    src = pkgs.fetchFromGitHub {
      inherit (old.src) owner repo;
      rev = "670189db7eb4f474343411a30a97b01f74b5a5fc";
      hash = "sha256-6cbeVN6w0j+qOwzebHZlVu5u14eJEB30H+1ocOCKLlY=";
    };
  });
  minty = v.buildVimPlugin rec {
    pname = "minty";
    version = "2025-01-17-master";
    src = pkgs.fetchFromGitHub {
      owner = "nvzone";
      repo = pname;
      rev = "6dce9f097667862537823d515a0250ce58faab05";
      hash = "sha256-U6IxF/i1agIGzcePYg/k388GdemBtA7igBUMwyQ3d3I=";
    };
    dependencies = [volt];
  };
  volt = v.buildVimPlugin rec {
    pname = "volt";
    version = "2025-01-17-master";
    src = pkgs.fetchFromGitHub {
      owner = "nvzone";
      repo = pname;
      rev = "f02b065caf0327bf4d443ff6d91cb0edd6948ddb";
      hash = "sha256-2SO847Un74kNFGxARaebB+WCCgexnaJdjUkQLZ6ROQ8=";
    };
  };
  menu = v.buildVimPlugin rec {
    pname = "menu";
    version = "2025-01-17-master";
    src = pkgs.fetchFromGitHub {
      owner = "nvzone";
      repo = pname;
      rev = "7769b17c2a131108c02b10e9f844e504aa605cc2";
      hash = "sha256-VEFUUo3h1Wg2+Yn7n83DZYoScKKLl6oIbmBt0WClAb0=";
    };
    dependencies = with p; [volt nvim-tree-lua];
  };
in {
  options = {
    programs.nixneovim.nvchad = {
      enable = mkEnableOption "NvChad";

      lazyPlugins = mkOption {
        type = with types; listOf package;
        default = with pkgs.master.vimPlugins;
          [
            # cmp-async-path
            # cmp-buffer
            # cmp-nvim-lsp
            # cmp-nvim-lua
            # cmp-path
            # cmp_luasnip
            # comment-nvim
            # friendly-snippets
            # gitsigns-nvim
            # indent-blankline-nvim
            # luasnip
            # nvim-autopairs
            # nvim-cmp
            # nvim-colorizer-lua
            # nvim-lspconfig
            # nvim-tree-lua
            # nvim-web-devicons
            # nvterm
            # telescope-nvim
            # which-key-nvim
          ]
          ++ (with pkgs.master.vimPlugins; [
            # default config uses this.
            # better-escape-nvim
            # conform-nvim
          ])
          ++ (with pkgs.vimPlugins; [
            nvim-treesitter.grammarPlugins
            # nvim-treesitter.withAllGrammars
            # (nvim-treesitter.withAllGrammars.overrideAttrs (_: let
            #   treesitter-parser-paths = pkgs.symlinkJoin {
            #     name = "treesitter-parsers";
            #     paths = nvim-treesitter.withAllGrammars.dependencies;
            #   };
            # in {
            #   postPatch = ''
            #     mkdir -p parser
            #     cp -r ${treesitter-parser-paths.outPath}/parser/*.so parser
            #   '';
            # }))
          ])
          ++ [
            # base46
            # nvchad-ui
            # nvchad
            # minty
            # volt
            # menu
          ];
        description = ''
          List of neovim plugins required by NvChad, available to lazy.nvim
          local plugins search path. Normally you don't need to change this
          option.
        '';
      };
      extraEarlyPlugins = mkOption {
        type = with types; listOf package;
        default = [];
        example = literalExpression ''
          with.pkgs.vimPlugins; [
            fidget-nvim
          ]
        '';
        description = ''
          extra plugins to load along with the usual nvchad ones, these are not
          lazy loaded so use sparingly.
        '';
      };

      extraLazyPlugins = mkOption {
        type = with types; listOf package;
        default = [];
        example = literalExpression ''
          with pkgs.vimPlugins; [
            neogit
            null-ls-nvim
          ]
        '';
        description = ''
          plugins search path.

          If you follow <link xlink:href="https://nvchad.com/docs/config/plugins"/>
          to setup additional plugins, you can use this option to avoid
          lazy.nvim downloading them.
        '';
      };
    };
  };

  config = mkIf cfg.nvchad.enable {
    xdg.configFile."nvim/lazyPlugins".source = pkgs.vimUtils.packDir {
      lazyPlugins = {
        start = cfg.nvchad.lazyPlugins ++ cfg.nvchad.extraLazyPlugins;
      };
    };
    # xdg.configFile."nvim/lua/core".source = "${nvchad}/lua/core";

    # xdg.configFile."nvim/lua/plugins".source = "${nvchad}/lua/plugins";
    # xdg.configFile."nvim/nvchad_init.lua".source = "${nvchad}/init.lua";

    programs.nixneovim = {
      enable = true;
      extraPackages = with pkgs; [
        # telescope-nvim
        # ripgrep
      ];
      extraPlugins = with pkgs.vimPlugins;
        [
          # base46
          # lazy-nvim
        ]
        # ++ [nvchad]
        ++ cfg.nvchad.extraEarlyPlugins;
      extraLuaPreConfig = let
        dependencies = pkgs.symlinkJoin {
          name = "treesitter-dependencies";
          # TODO: (low prio) make for the ability for the user to add their own things to path
          # TODO: (med prio) check that they exist? might not be needed.
          # paths = [] ++ pkgs.vimPlugins.nvim-treesitter.withAllGrammars.dependencies;
          # paths = [] ++ pkgs.vimPlugins.nvim-treesitter.grammarPlugins.dependencies;
        };
      in
        lib.mkDefault ''
          -- HACK: M. remove the default nvim parsers, they clash with treesitter.
          vim.opt.rtp:remove("${cfg.package}/lib/nvim")
          dofile(vim.fn.stdpath "config" .. "/init_nv.lua")
          -- HACK: M. make sure that treesitter's dependencies are in view, otherwise bad things happen, the
          -- alternative is to load treesitter non-lazy, which is worse, and murders startup time.
          -- HACK: H. This needs to be at the end since lazy clears rtp by default
          vim.opt.rtp:append("${dependencies}")
        '';
    };
  };
}
#
#   -- dofile(vim.fn.stdpath "config" .. "/nvchad_init.lua")
#   -- HACK: M. remove the default nvim parsers, they clash with treesitter.
#   vim.opt.rtp:remove("${cfg.package}/lib/nvim")
#   -- HACK: M. make sure that treesitter's dependencies are in view, otherwise bad things happen, the
#   -- alternative is to load treesitter non-lazy, which is worse, and murders startup time.
#   vim.opt.rtp:append("${dependencies}")
#   vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
#   vim.g.mapleader = " "
#
#   -- bootstrap lazy and all plugins
#   -- local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
#
#   -- if not vim.uv.fs_stat(lazypath) then
#   --   local repo = "https://github.com/folke/lazy.nvim.git"
#   --   vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
#   if not vim.loop.fs_stat(vim.g.base46_cache) then
#     require("base46").compile()
#   end
#
#   -- vim.opt.rtp:prepend(lazypath)
#
#   local lazy_config = require "configs.lazy"
#
#   -- load plugins
#   require("lazy").setup({
#     {
#       "NvChad/NvChad",
#       lazy = false,
#       branch = "v2.5",
#       import = "nvchad.plugins",
#     },
#
#     { import = "plugins" },
#   }, lazy_config)
#
#   -- load theme
#   dofile(vim.g.base46_cache .. "defaults")
#   dofile(vim.g.base46_cache .. "statusline")
#
#   require "options"
#   require "nvchad.autocmds"
#
#   vim.schedule(function()
#     require "mappings"
#   end)
# '';

