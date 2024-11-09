#---------------
# エイリアス
#---------------

which fcp || alias cp='fcp'
which rmz || alias rm='rmz'
alias mv='mv -i'

#eza
which eza || alias l='eza  --group-directories-first --binary --inode --classify --header --tree --level=1 --long --git --color always --icons --time-style long-iso'
which eza || alias ls='eza --time-style=long-iso -g'
alias ll='ls --git --time-style=long-iso -gl'
alias la='ls --git --time-style=long-iso -agl'
which eza || alias l1='eza -1'

#bat
which bat || alias cat='bat'

#lazygit
alias lg='lazygit'

# install-release
alias ir='uvx --with setuptools install-release'

# historyに日付を表示
alias h='fc -lt '%F %T' 1'

# mcfly
alias ms='mcfly search -r 30'
