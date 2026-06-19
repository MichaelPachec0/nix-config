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
          size = 10000000;
        in {
          inherit size;
          save = size;
          expireDuplicatesFirst = true;
          extended = true;
          ignorePatterns = ["rm *" "pkill *"];
        };

        initExtra = ''
          ZSH_AUTOSUGGEST_STRATEGY=(completion history)
          RPS1='$(kubectx_prompt_info)'
          PROMPT='$(kube_ps1)'$PROMPT
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
          # Public: easy to use git commit with the specified date.
          #

          # date -  date to be parsed as date to use in git commit.
          # message - commit message to use.
          # d - force add extra day (optional)
          #
          # Examples
          #
          #   gwd "hello world"
          #   # reads last commit
          #   # checks if the -d flag is set, if not coin flip, if true, then
          #   # changes day, if not keeps day. (discards day if its in then
          #   # future)
          #   # If same day is set, then coinflip on hour, look above ^
          #   # same for minute (if minute is 59 then roll hour)
          #   # passthrough seconds.

          #   # => "GIT_COMITTER_DATE='2023-03-24T18:46:49-07:00'; git commit --date='2023-03-24T18:46:49-07:00' -s -m "hello world"
          # function gwd() {
          #   command="git log -1 --format=%cd --date:format:"
          #   day=$(''${command}"%d"})
          #   hour=$(''${command}"%h")
          #   min=$(''${command}"%M")
          #   # parse all arguments
          #
          #   # flips
          #   if [[ $# == 3 ]]; then
          #     day=$(($day +  1))
          #     else
          #       # 50/50 coinflip
          # }
          # Public: shortened version of hyprctl monitor movement
          function mv2mon() {
            command hyprctl dispatch moveworkspacetomonitor "$@";
          }
          if command -v nix-your-shell > /dev/null; then
            nix-your-shell zsh | source /dev/stdin
          fi
          eval "$(direnv hook zsh)"
          # NOTE: for distrobox compat
          PATH=$PATH:$HOME/.local/bin
        '';
        shellAliases = let
          # Maybe set a global default timer?
          watchTimer = 5;

          watchCommand = {
            command,
            timer ? watchTimer,
            # make this a list? dont know how important that might be
            extraCommands ? "",
            envVars ? "",
          }: let
            cmd = "${envVars} ${command} ${extraCommands}";
          in "watch -n${toString timer} --color ${cmd} ";

          watchAlias = {
            alias,
            timer ? watchTimer,
            # see above
            extraCommands ? "",
            envVars ? "",
          }:
            watchCommand {
              command = "$(alias ${alias} | cut -c8- | head -c -2 | sed \"s/'/\'\\''/g\")";
              inherit timer extraCommands envVars;
            };
          currentDate = ''
            $(git show HEAD --summary | grep Date | cut -d " " -f 4-)
          '';
        in {
          # nix specific
          hmsf = "home-manager switch -L --option access-tokens \"github.com=$(gh auth token)\" --flake";
          nrsf = "sudo nixos-rebuild switch -L --option access-tokens \"github.com=$(gh auth token)\" --flake";

          # kitty specific
          icat = "kitty +kitten icat";
          sshk = "kitty +kitten ssh";

          # git specific
          # should expand to "watch -n5 --color $(alias glola | cut -c8- | head -c -2 | sed \"s/'/\'\\''/g\") --color";
          wgit = watchAlias {
            alias = "glola";
            extraCommands = "--color";
            envVars = "PAGER=cat";
          };
          # git rebase preserving date and user
          # https://gist.github.com/ugultopu/0b6412674073a5b603f8227cb108441c?permalink_comment_id=4853683#gistcomment-4853683
          # gpg? i might need to check if the git email is me?
          gitr = let
            envV = ''%s%nexec GIT_COMMITTER_DATE="%cD" GIT_COMMITTER_NAME="%cn" GIT_COMMITTER_EMAIL="%ce"  git commit --amend --no-edit --reset-author --date="%cD"'';
          in "git -c rebase.instructionFormat='${envV}' rebase -i";
          gitra = "git rebase --abort";
          boop = "touch";
          gitamn = ''
            GIT_COMMITTER_DATE="${currentDate}" GIT_AUTHOR_DATE="${currentDate}" git commit --amend --no-edit
          '';
          gitam = ''
            GIT_COMMITTER_DATE="${currentDate}" GIT_AUTHOR_DATE="${currentDate}" git commit --amend
          '';
          # TODO: need to not hardcode the host and builder
          rnrsf = ''
            NIX_SSHOPTS="-i ~/.ssh/id_ed25519_sk_791"; sudo --preserve-env=NIX_SSHOPTS nixos-rebuild switch --log-format internal-json -v --flake ".#nyx" -option access-tokens "github.com=$(gh auth token)" --show-trace --build-host "deploy@172.30.0.5" --fast |& nom --json
          '';
          # rsync --recursive --compress --info=PROGRESS2 ~/Downloads/JLink_Linux_V812e_x86_64.tgz  --exclude="result" kore:~
          rcpy = ''
            rsync --recursive --compress --info=PROGRESS2  --exclude="result" kore:~
          '';
          vnote = ''
            vim $(date +%Y-%m-%d_%H:%M)_$1.txt
          '';
          lag = "lazygit";
        };
        initExtraFirst = ''
          # The oh-my-zsh docker plugin re-copies its completion from the
          # (read-only) nix store into $ZSH_CACHE_DIR on every startup. podman's
          # docker-compat reports version <23, so it always takes the legacy
          # `cp` branch, which fails with EACCES once the cached file inherits
          # the store's read-only mode. Make it writable before omz loads so the
          # copy can overwrite it. Runs before plugins; self-heals a cache wipe.
          () {
            local f="''${ZSH_CACHE_DIR:-$HOME/.cache/oh-my-zsh}/completions/_docker"
            [[ -f "$f" ]] && chmod u+w "$f"
          }
        '';
      };
    };
  };
}
