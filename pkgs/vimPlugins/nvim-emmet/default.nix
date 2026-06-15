{
  vimUtils,
  fetchFromGitHub,
  ...
}:
vimUtils.buildVimPlugin rec {
  pname = "nvim-emmet";
  version = "2023-09-28";
  src = fetchFromGitHub {
    owner = "olrtg";
    repo = pname;
    rev = "eaccea7a5378d97bb674125295e893480afdb870";
    hash = "sha256-yEDU6yATAyZwASF7BO+t1lI/4csh2GJiu4MoODi2NH4=";
  };
}
