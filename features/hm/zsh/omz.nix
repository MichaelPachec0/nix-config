{...}: {
  imports = [];
  options = {};
  config = {
    programs.zsh = {
      oh-my-zsh = {
        enable = true;
        plugins = [
          # "thefuck"
          "aliases"
          "battery"
          "colored-man-pages"
          "colorize"
          "cp"
          "docker"
          "docker-compose"

          # gone: https://github.com/ohmyzsh/ohmyzsh/commit/ff62d39f023fbe2872078ce82ea9704b1bf09ea6
          # "docker-machine"

          "gitfast"
          "git"
          "dotenv"
          "encode64"
          "extract"
          "fancy-ctrl-z"
          "frontend-search"
          #"fzf"
          "git-escape-magic"
          "git-flow"
          "gh"
          "golang"

          "kubectl"
          "kubectx"
          "kube-ps1"
          "last-working-dir"
          "nmap"
          "node"
          "npm"
          "postgres"
          "python"

          # gone: https://github.com/ohmyzsh/ohmyzsh/pull/12576
          # "ripgrep"

          "rust"
          "safe-paste"
          "ssh-agent"
          "sudo"
          "systemd"
          #"systemadmin"
        ];
      };
    };
  };
}
