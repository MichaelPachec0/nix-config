# NOTE: taken from https://github.com/mahmoudk1000/nix-config/blob/627015f232083e37a213b11ff760522b4de5510a/modules/programs/neovim/autotools-ls.nix
{pkgs, ...}:
with pkgs; let
  tree-sitter-lsp = python3.pkgs.buildPythonPackage rec {
    pname = "lsp-tree-sitter";
    version = "0.0.14";
    format = "pyproject";
    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-2ut/eo2uLrB1oQ7M8iH5hhm9xoEajeVqmrkYTePCe4g=";
    };

    propagatedBuildInputs = with pkgs.python3Packages; [
      colorama
      jinja2
      jsonschema
      pygls
      tree-sitter
    ];

    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      setuptools-generate
      setuptools-scm
    ];
  };

  makeLS = fetchGit {
    name = "vender_make";
    url = "https://github.com/alemuller/tree-sitter-make.git";
    rev = "a4b9187417d6be349ee5fd4b6e77b4172c6827dd";
  };

  tree-sitter-languages = python3.pkgs.buildPythonPackage rec {
    pname = "tree-sitter-languages";
    version = "1.8.0";
    src = pkgs.fetchFromGitHub {
      owner = "grantjenks";
      repo = "py-${pname}";
      rev = "83c509f8dd80a04b3bf37e11bd2ab0e8c4df0876";
      hash = "sha256-UXYlHAXQkxZfZ4xT3VChVXevglxTnwDrMqD8A44zxLU=";
    };

    buildInputs = with pkgs.python3Packages; [
      tree-sitter
      cython
    ];

    buildPhase = ''
      runHook preBuild

      ${python3.pythonOnBuildForHost.interpreter} - <<EOF
      from tree_sitter import Language

      Language.build_library(
        "tree_sitter_languages/languages.so",
          [
            "${makeLS}"
          ]
        )
      EOF

      ${python3.pythonOnBuildForHost.interpreter} setup.py bdist_wheel

      runHook postBuild
    '';
  };
in
  # python3.pkgs.buildPythonPackage rec {
  #   pname = "autotools-language-server";
  #   version = "0.0.13";
  #   format = "pyproject";
  #
  #   src = pkgs.fetchPypi {
  #     inherit pname version;
  #     hash = "sha256-xYHGmDeVyXrDzVqmpqaAKylaVB+hj+grZBF+sHAvFQg=";
  #   };
  #
  #   propagatedBuildInputs = [
  #     tree-sitter-languages
  #     tree-sitter-lsp
  #   ];
  #
  #   nativeBuildInputs = with pkgs.python3Packages; [
  #     setuptools
  #     setuptools-generate
  #     setuptools-scm
  #   ];
  # }
  python3.pkgs.buildPythonPackage rec {
    pname = "autotools-language-server";
    version = "0.0.13";
    format = "pyproject";

    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-xYHGmDeVyXrDzVqmpqaAKylaVB+hj+grZBF+sHAvFQg=";
    };

    propagatedBuildInputs = with pkgs; [
      tree-sitter-languages
      tree-sitter-lsp
    ];

    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      setuptools-generate
      setuptools-scm
    ];
  }
