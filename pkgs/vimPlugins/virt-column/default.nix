{pkgs, ...}:
pkgs.vimUtils.buildVimPlugin rec {
    name = "virt-column.nvim";
    src = pkgs.fetchFromGitHub {
        owner = "lukas-reineke";
        repo = name;
        rev = "v1.5.5";
        hash = "sha256-6EbEzg2bfoHmVZyggwvsDlW9OOA4UkcfO0qG0TEDKQs=";
      };
  }
