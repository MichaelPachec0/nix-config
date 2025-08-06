{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
  pname = "neotest-gtest";
  version = "2023-09-28";
  src = pkgs.fetchFromGitHub {
    owner = "alfaix";
    repo = pname;
    rev = "e3d828a103f5a81fb14fee21e32c9c9223d48572";
    hash = "sha256-+AHLrZ6PoJ16bOsTDtzPGALdVadtwMTn4FMBbzVjSGg=";
  };
  # TODO:  (med prio) disable tests for now!
  # nvimRequireCheck = "";
  # Vim plugin with a test lua file
  doCheck = false;
}
