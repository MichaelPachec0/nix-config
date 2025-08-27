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
    version = "2025-09-03-master";
    src = pkgs.fetchFromGitHub {
      inherit (old.src) owner repo;
      # working
      # rev = "6f25b2739684389ca69ea8229386c098c566c408";
      # hash = "sha256-w/ZRxWxuU/ECq3ntkXek5BgJiBcUCBOjrvNBc4U94V4=";
      # latest
      # rev = "29ebe31ea6a4edf351968c76a93285e6e108ea08";
      # hash = "sha256-2C/UwbvVshE7qSO6QJYzZA5i9d+OC/EWLRedqxUp4YM=";
      # test
      # rev = "65ffd7dbb9b9d89343d9a0926f3c61d63d2e8d0e";
      # hash = "sha256-nOJlQBhYwr/KDHPbxI8VGQ9ZNfeECBfTtEnLe3bIgiM=";
      # ERROR: commits past this will kill lsp's with a crytpic mapping error
      # WARN: There was a change to mappings in nvim 0.11, where lspconfig doesn't
      # any config for nvim (keymappings) it only sets configs for lsp's now
      # TODO: investigate and migrate in the future.
      # see https://github.com/NvChad/starter/commit/2ef0168470ad6d1bc68e44177fa05b43110d9e25
      # and https://github.com/NvChad/NvChad/commit/46b15ef1b9d10a83ab7df26b14f474d15c01e770
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
      version = "2025-09-03-master";
      inherit (old.src) owner repo;
      rev = "8cbf1026db2b58d27ee976d780989059eac37fa0";
      hash = "sha256-HVQMgTKgFGZO2aqZZayl5lmkub6rEli+2S5v9uco5IA=";
    };
    # this should still work
    patches = [
      # ./ui.patch
    ];
  });
  base46 = pkgs.vimPlugins.base46.overrideAttrs (old: {
    version = "2025-09-03-master";
    src = pkgs.fetchFromGitHub {
      inherit (old.src) owner repo;
      rev = "0094095ed60aa55f7148bc1e783b0156f3e7f4f8";
      hash = "sha256-K37nU7bBm0AwHhZlgrMoTWpUw8aOyIi6m9dDtL34mFY=";
    };
  });
  minty = v.buildVimPlugin rec {
    pname = "minty";
    version = "2025-09-03-master";
    src = pkgs.fetchFromGitHub {
      owner = "nvzone";
      repo = pname;
      rev = "aafc9e8e0afe6bf57580858a2849578d8d8db9e0";
      hash = "sha256-jdz0cR1uz1EdxFCuxndsK9gyTZ2jg8wdYA0v33SevOg=";
    };
    dependencies = [volt];
  };
  volt = v.buildVimPlugin rec {
    pname = "volt";
    version = "2025-09-03-master";
    src = pkgs.fetchFromGitHub {
      owner = "nvzone";
      repo = pname;
      rev = "7b8c5e790120d9f08c8487dcb80692db6d2087a1";
      hash = "sha256-szq/QBI2Y6DKeqBuJ8qA4LlGYnarLT6D/fvwepIgSVc=";
    };
  };
  menu = v.buildVimPlugin rec {
    pname = "menu";
    version = "2025-01-17-master";
    src = pkgs.fetchFromGitHub {
      owner = "nvzone";
      repo = pname;
      rev = "7a0a4a2896b715c066cfbe320bdc048091874cc6";
      hash = "sha256-4GfQ6Mo32rsoQAXKZF9Bpnm/sms2hfbrTldpLp5ySoY=";
    };
    dependencies = with p; [volt nvim-tree-lua neo-tree-nvim nui-nvim plenary-nvim];
  };
in {
  options = {
    programs.nixneovim.nvchad = {
      enable = mkEnableOption "NvChad";

      lazyPlugins = mkOption {
        type = with types; listOf package;
        default = with pkgs.master.vimPlugins;
          [
            cmp-async-path
            cmp-buffer
            cmp-nvim-lsp
            cmp-nvim-lua
            cmp-path
            cmp_luasnip
            comment-nvim
            friendly-snippets
            gitsigns-nvim
            indent-blankline-nvim
            luasnip
            # nvchad-ui
            nvim-autopairs
            nvim-cmp
            nvim-colorizer-lua
            nvim-lspconfig
            nvim-tree-lua
            nvim-web-devicons
            nvterm
            telescope-nvim
            which-key-nvim
          ]
          ++ (with pkgs.master.vimPlugins; [
            # default config uses this.
            better-escape-nvim
            conform-nvim
          ])
          ++ (with pkgs.vimPlugins; [
            nvim-treesitter.withAllGrammars
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
          ++ [base46 nvchad-ui nvchad minty volt menu];
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
        ripgrep
      ];
      extraPlugins = with pkgs.vimPlugins;
        [
          base46
          lazy-nvim
        ]
        # ++ [nvchad]
        ++ cfg.nvchad.extraEarlyPlugins;
      extraLuaPreConfig = let
        dependencies = pkgs.symlinkJoin {
          name = "treesitter-dependencies";
          # TODO: (low prio) make for the ability for the user to add their own things to path
          # TODO: (med prio) check that they exist? might not be needed.
          paths = [] ++ pkgs.vimPlugins.nvim-treesitter.withAllGrammars.dependencies;
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

