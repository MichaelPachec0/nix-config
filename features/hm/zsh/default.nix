{pkgs, ...}: {
  imports = [./omz.nix ./plugins.nix];
  options = {};
  config = {
    home.packages = with pkgs; [socat];
    programs = {
      zsh = {
        enable = true;
        enableCompletion = true;
        enableAutosuggestions = true;
        dotDir = ".config/zsh";
        enableSyntaxHighlighting = true;
        # profileExtra = ''
        #   PATH=$PATH:$HOME/.local/bin
        # '';
        history = let
          size = 10000;
        in {
          inherit size;
          save = size;
          expireDuplicatesFirst = true;
          extended = true;
        };

        initExtra = ''
          ZSH_AUTOSUGGEST_STRATEGY=(completion history)
          RPS1='$(kubectx_prompt_info)'
          PROMPT='$(kube_ps1)'$PROMPT
          alias icat='kitty +kitten icat'
          # setopt ksh_arrays

          # Public: insert sign-off by default with git.
          # (I always want to sign off commits since they are already gpg signed)
          #
          # message: git message to have.
          #
          # Examples:
          #
          #   git -m "Hello World"
          #   # => git commit -s -m "Hello World"
          # Executes the command with sign-off if commit is the sub-command,
          # else does passthrough the command to the actual git command to
          # execute.
          function git() {
            case $* in
              commit* ) shift 1; command git commit -s "$@";;
              # NOTE: otherwise bypass it and call git with rest of  the arg
              * ) command git "$@" ;;
            esac
          }
          function mv2mon() {
            command hyprctl dispatch moveworkspacetomonitor "$@";
          }
          if command -v nix-your-shell > /dev/null; then
            nix-your-shell zsh | source /dev/stdin
          fi
        '';
        shellAliases = {
          hmsf = "home-manager switch -L --flake";
          nrsf = "sudo nixos-rebuild switch -L --flake";
        };
        initExtraFirst = "";

      };
    };
  };
}
