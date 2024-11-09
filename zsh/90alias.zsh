#---------------
# エイリアス
#---------------

command -v fcp 2>&1 >/dev/null || alias cp='fcp'
command -v rmz 2>&1 >/dev/null  || alias rm='rmz'
alias mv='mv -i'

#eza
command -v eza 2>&1 >/dev/null || alias l='eza  --group-directories-first --binary --inode --classify --header --tree --level=1 --long --git --color always --icons --time-style long-iso'
command -v eza 2>&1 >/dev/null || alias ls='eza --time-style=long-iso -g'
alias ll='ls --git --time-style=long-iso -gl'
alias la='ls --git --time-style=long-iso -agl'
command -v eza 2>&1 >/dev/null || alias l1='eza -1'

#bat
command -v bat 2>&1 >/dev/null || alias cat='bat'

#lazygit
alias lg='lazygit'

# install-release
alias ir='uvx --with setuptools install-release'

# historyに日付を表示
alias h='fc -lt '%F %T' 1'

# mcfly
alias ms='mcfly search -r 30'
