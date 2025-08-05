{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "virt-column.nvim";
  version = "v2.0.0";
  src = pkgs.fetchFromGitHub {
    owner = "lukas-reineke";
    repo = pname;
    rev = version;
    hash = "sha256-VSeOw+MKLeR/iRRuMe4Ru2DNXWGQgObixfgqN9S7LBw=";
  };

  nvimSkipModule = [
    "virt-column.config.types"
  ];
  nativeBuildInputs = with pkgs.luajitPackages; [luacheck];
}
