#---------------
# PATH
#---------------
# パスを追加したい場合
export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/setup/dotfiles/bin:$PATH"

# mise (Rustより先に読み込む)
eval "$(~/.local/bin/mise activate zsh)"

# cargo
. "$HOME/.cargo/env"

export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
