{ pkgs, ... }: {
  imports = [ ./omz.nix ./plugins.nix ];
  options = { };
  config = {
    programs = {
      zsh = {
        enable = true;
        enableCompletion = true;
        enableAutosuggestions = true;
        dotDir = ".config/zsh";
        enableSyntaxHighlighting = true;

        initExtra = ''
          ZSH_AUTOSUGGEST_STRATEGY=(completion history)
          RPS1='$(kubectx_prompt_info)'
          PROMPT='$(kube_ps1)'$PROMPT
          alias icat='kitty +kitten icat'
          # setopt ksh_arrays

          # this is to enable sign-off by default
          function git() {
            case $* in
            commit* ) shift 1; command git commit -s "$@";;
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
