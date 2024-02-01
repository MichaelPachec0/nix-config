{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin {
  pname = "wtf.nvim";
  version = "0.0.1-master";
  src = pkgs.fetchFromGitHub {
    owner = "piersolenski";
    repo = "wtf.nvim";
    rev = "3247bf923e93fb0b65920beb60b10778461d1234";
    hash = "sha256-zr6ONeKNWBPZPz4VNPv0BK5EEXikC+efmsBB15dXBRQ=";
  };
  # doCheck = false;
  # nativeBuildInputs = with pkgs;[git] ;
  patches = [./test.patch];

  dependencies = with pkgs.vimPlugins; [nui-nvim plenary-nvim neotest-plenary];
  PLENARY_DIR = "${pkgs.vimPlugins.plenary-nvim}";
  NUI_DIR = "${pkgs.vimPlugins.nui-nvim}";
}
