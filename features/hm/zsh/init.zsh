
ZSH_AUTOSUGGEST_STRATEGY=(completion history)
RPS1='$(kubectx_prompt_info)'
PROMPT='$(kube_ps1)'$PROMPT
alias icat='kitty +kitten icat'
# setopt ksh_arrays

# Public: insert sign-off by default with git.
# (I always want to sign off commits since i already gpg sign them
# as well)
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
            # NOTE: shift will remove the commit bit.
            # TODO: (low prio) shift might be needed?
        commit* ) shift 1; command git commit -s "$@" ;;
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
function gwd() {
    command="git log -1 --format=%cd --date:format:"
day=$(''${command}"%d"})
hour=$(''${command}"%h")
min=$(''${command}"%M")
# parse all arguments

# flips
if [[ $# == 3 ]]; then
    day=$(($day +  1))
else
    # 50/50 coinflip

}
# Public: shortened version of hyprctl monitor movement
function mv2mon() {
    command hyprctl dispatch moveworkspacetomonitor "$@";
}
if command -v nix-your-shell > /dev/null; then
    nix-your-shell zsh | source /dev/stdin
fi
eval "$(direnv hook zsh)"
