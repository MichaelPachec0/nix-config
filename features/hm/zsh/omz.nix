{ ... }: {
  imports = [ ];
  options = { };
  config = {
    programs.zsh = {
      oh-my-zsh = {
        enable = true;
        plugins = [
          "thefuck"
          "aliases"
          "battery"
          "colored-man-pages"
          "colorize"
          "cp"
          "docker"
          "docker-compose"
          "docker-machine"
          "gitfast"
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
          "ripgrep"
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

