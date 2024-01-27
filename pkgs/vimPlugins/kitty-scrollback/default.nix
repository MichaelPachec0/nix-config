{pkgs, ...}:
  pkgs.vimUtils.buildVimPlugin rec {
    pname = "kitty-scrollback.nvim";
    version = "2.2.0";
    src = pkgs.fetchFromGitHub {
      owner = "mikesmithgh";
      repo = pname;
      rev = "v${version}";
      hash = "sha256-iM7oO7E8bcPC12Udoz+KkBlNJCy1wvEGYGwZDusU9qA=";
    };
  }

