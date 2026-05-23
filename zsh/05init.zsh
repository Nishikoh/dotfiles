# -----------------------------
# External Tool Initialization
# -----------------------------

# brew (Linux/macOS両対応)
if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# starship
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# zoxide
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# fzf
if command -v fzf >/dev/null 2>&1; then
    source <(fzf --zsh)
fi

# wt
if command -v wt >/dev/null 2>&1; then
    eval "$(command wt config shell init zsh)"
fi
