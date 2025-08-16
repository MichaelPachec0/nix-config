{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
in {
  # LSP servers / formatters / linters are developer tooling -- only install them
  # on machines that opt in via `devMachine.enable` (declared in
  # features/nixos/common/default.nix). neovim itself is installed unconditionally
  # via programs.neovim in that same module, so a non-dev host still gets an editor.
  config = lib.mkIf config.devMachine.enable {
    environment.systemPackages = with pkgs;
      [
        gnumake # fzf
        delta # used for syntax highlight, mainly used in telescope-undo-nvim
        chafa # for terminal image support, used by media-files nvim plugin

        # lua stuff
        stylua # lua formatter
        lua-language-server # lua lsp
        selene # lua linter

        # nix stuff
        nil # lsp
        nixd # other lsp for nix
        statix # static checker (linter/code actions)
        manix # lookup nixpkgs (lib... ect)
        alejandra # opinionated formatter

        # for lsps that require node, is this needed?
        # nodejs_20

        # go stuff
        gopls # go lsp
        gomodifytags # modify go struct tags easily
        impl #  generates method stubs for implementing an interface.
        # ex
        # $ impl 'f *File' io.ReadWriteCloser
        # func (f *File) Read(p []byte) (n int, err error) {
        # 	panic("not implemented")
        # }
        #
        # func (f *File) Write(p []byte) (n int, err error) {
        # 	panic("not implemented")
        # }
        #
        # func (f *File) Close() error {
        # 	panic("not implemented")
        # }
        #
        # # You can also provide a full name by specifying the package path.
        # # This helps in cases where the interface can't be guessed
        # # just from the package name and interface name.
        # $ impl 's *Source' golang.org/x/oauth2.TokenSource
        # func (s *Source) Token() (*oauth2.Token, error) {
        #     panic("not implemented")
        # }

        # WARN: enable once https://github.com/NixOS/nixpkgs/pull/331088 gets merged
        # cpplint

        yamllint # yaml linter
        actionlint # linter for github actions

        # elixir-ls
        # erlang-ls

        commitlint # linter for git commits

        # bash stuff
        bash-language-server # bash lsp
        beautysh # bash beautifier for the masses TODO: integrate with conform
        shfmt

        taplo # toml lsp and formatter

        hadolint # docker linter
        docker-compose-language-service # docker compose lsp
        dockerfile-language-server-nodejs # docker lsp

        deno # for deno fmt
        typescript
        code-minimap
        vscode-langservers-extracted # this did not work in unstable

        # c stuff
        # clang_format, clangd, clang_check
        clang-tools
        # ERROR: DOES NOT COMPILE 
        # autotools-language-server # make lsp
        bear # for helping clangd with compile_commands.json

        # python stuff
        basedpyright # python lsp, alterntive to pyright
        black # Uncompromising Python code formatter
        ruff # linter/fmt

        stow # manages symlinks, and used for symlinking dotfiles

        # typescript/javascript
        typescript-language-server
        prettierd # multi-lang formatter
        stable.eslint # code action / linter
        # microsoft's html/css/json/eslint lsp's
        tailwindcss
        tailwindcss-language-server # tailwindcss lsp
        # 2025-11-18: removed because its unmaintained
        # nodePackages.jsonlint # json lint
        # TODO: (high) see ref https://github.com/NixOS/nixpkgs/issues/384795
        #biome # web linter/fmt for JavaScript, TypeScript, JSX, TSX, JSON, CSS and GraphQL
        fixjson

        # eslint_d # code action / linter
        emmet-language-server
        # swift
        # swift-format
        # sourcekit-lsp
        # TODO: decide if this needs to stay here or general programs.nix
        # lazygit
        arduino-language-server
        arduino-cli
      ]
      # ++ (with pkgs.nodePackages; [
      ++ (with pkgs; [
        cspell # mutli-lang spell checker
      ])
      ++ (with pkgs.ocamlPackages; [
        ocaml-lsp # ocaml-lsp
      ]);
  };
}
# NOTE: these is handled as part of the vscode module
# Doing so means a more predictable path for the server.
# vscode-extensions.ms-python.vscode-pylance
# vscode-lldb

# extraPackages = with pkgs;
#   [
#     # lldb
#   ]
#   ++ (with pkgs; [
#     lua-language-server # lua lsp
#     stylua # lua formatter
#     # used for syntax highlight, mainly used in telescope-undo-nvim
#     delta
#     # for terminal image support, used by media-files nvim plugin
#     chafa
#
#     # nix stuff
#     nil # lsp
#     statix # static checker (linter/code actions)
#     manix # lookup nixpkgs (lib... ect)
#     alejandra # opinionated formatter
#     # NOTE: these is handled as part of the vscode module
#     # Doing so means a more predictable path for the server.
#     # vscode-extensions.ms-python.vscode-pylance
#     # vscode-lldb
#
#     # c lsp
#     clang-tools
#     # for lsps that require node
#     nodejs-slim_20
#     gopls
#     elixir-ls
#     erlang-ls
#   ])
#   ++ (with pkgs.nodePackages_latest; [
#     # typescript/javascript
#     typescript-language-server
#     prettier # formatter
#     eslint_d # code action / linter
#     # microsoft's html/css/json/eslint lsp's
#     vscode-langservers-extracted
#     tailwindcss
#   ])
#   ++ (with pkgs.ocamlPackages; [ocaml-lsp]);

