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
if command -v eza &>/dev/null; then
	alias lsi='eza'
	alias l='eza  --group-directories-first --binary --inode --classify --header --tree --level=1 --long --git --color always --icons --time-style long-iso'
	alias lsis='eza --time-style=long-iso -g'
	alias ll='eza --git --time-style=long-iso -gl'
	alias la='eza --git --time-style=long-iso -agl'
	alias l1='eza -1'
fi

#bat
set_alias_if_command_exists "bat" "cat"

#lazygit
alias lg='lazygit'

# install-release
alias ir='uvx --with setuptools install-release'

# historyに日付を表示
alias h="fc -lt '%F %T' 1"

# mcfly
alias ms='mcfly search -r 30 -f 1'

# mcfly-fzf
alias mf='mcfly-fzf-history-widget'

# fzf + bat
alias fb="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"

alias ai-msg='bunx copilot --model gpt-5-mini -p "`git --no-pager diff --staged`の内容からcommit messageを日本語で考えて。実際にcommitはしないで"'

alias set-aws-profile='export AWS_PROFILE=$(aws configure list-profiles | fzf)'

# beep (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
	alias beep='for i in {1..3}; do afplay /System/Library/Sounds/Submarine.aiff; done'
fi
