{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  name = "none-ls-extras-nvim";
  pname = "none-ls-extras-nvim";
  src = pkgs.fetchFromGitHub {
    owner = "nvimtools";
    repo = "none-ls-extras.nvim";
    rev = "336e84b9e43c0effb735b08798ffac382920053b";
    hash = "sha256-UtU4oWSRTKdEoMz3w8Pk95sROuo3LEwxSDAm169wxwk=";
  };
  doInstallCheck = false;
  # nvimRequireCheck = "";
  doCheck = false;
}
# >   - none-ls.diagnostics.eslint
# >   - none-ls.diagnostics.yamllint
# >   - none-ls.diagnostics.flake8
# >   - none-ls.diagnostics.ruff
# >   - none-ls.diagnostics.eslint_d
# >   - none-ls.diagnostics.cpplint
# >   - none-ls.formatting.jq
# >   - none-ls.formatting.beautysh
# >   - none-ls.formatting.eslint
# >   - none-ls.formatting.latexindent
# >   - none-ls.formatting.ruff_format
# >   - none-ls.formatting.standardrb
# >   - none-ls.formatting.rustfmt
# >   - none-ls.formatting.autopep8
# >   - none-ls.formatting.ruff
# >   - none-ls.formatting.trim_newlines
# >   - none-ls.formatting.yq
# >   - none-ls.formatting.reformat_gherkin
# >   - none-ls.formatting.eslint_d
# >   - none-ls.formatting.trim_whitespace
# >   - none-ls.code_actions.eslint
# >   - none-ls.code_actions.eslint_d

