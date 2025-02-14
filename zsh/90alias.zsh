#---------------
# alias
#---------------

set_alias_if_command_exists() {
	# modern linux command. +i -> improve
	command -v "$1" &>/dev/null && alias "$2"i="$1"
}

set_alias_if_command_exists "fcp" "cp"
set_alias_if_command_exists "rmz" "rm"
alias mv='mv -i'

#eza
set_alias_if_command_exists "eza" "ls"
if command -v eza &>/dev/null; then
	alias l='eza  --group-directories-first --binary --inode --classify --header --tree --level=1 --long --git --color always --icons --time-style long-iso'
	alias lsis='eza --time-style=long-iso -g'
	alias ll='exa --git --time-style=long-iso -gl'
	alias la='exa --git --time-style=long-iso -agl'
	alias l1='eza -1'
fi

#bat
set_alias_if_command_exists "bat" "cat"

#lazygit
alias lg='lazygit'

# install-release
alias ir='uvx --with setuptools install-release'

# historyに日付を表示
alias h='fc -lt '%F %T' 1'

# mcfly
alias ms='mcfly search -r 30 -f 1'

# mcfly-fzf
alias mf='mcfly-fzf-history-widget'

# fzf + bat
alias fb="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"

# devbox pull global
alias devbox-pull='devbox global pull https://github.com/Nishikoh/devbox.git'

alias ai-msg='gh copilot suggest "Give me the proper commit message for the following diff /n $(git diff --staged)"'

alias set-aws-profile='export AWS_PROFILE=$(aws configure list-profiles | fzf)'
# alias aws='uvx --from awscli aws' # pypiからインストールするとv1が入るので、v2を使うには公式インストーラーからインストールする必要がある

alias beep='for i in {1..3}; do afplay /System/Library/Sounds/Submarine.aiff; done'
