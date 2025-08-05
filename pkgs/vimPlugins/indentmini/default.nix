{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "indentmini.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "nvimdev";
    repo = "${pname}";
    rev = "6615c19d5221576e39c030cfe60cb4ce3ca4be65";
    sha256 = "qQ1kV0d7J91YuT/8lp5IE7Ht+pNcO3hXJqHh6axpsNA=";
  };
}
