{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "inlay-hints.nvim";
  version = "2024-01-24-master";
  src = pkgs.fetchFromGitHub {
    owner = "simrat39";
    repo = "${pname}";
    rev = "006b0898f5d3874e8e528352103733142e705834";
    hash = "sha256-cDWx08N+NhN5Voxh8f7RGzerbAYB5FHE6TpD4/o/MIQ=";
  };
}
