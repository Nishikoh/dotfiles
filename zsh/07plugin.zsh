# -----------------------------
# Plugins
# -----------------------------

# zsh設定ディレクトリのパス
ZSH_CONFIG_PATH="${ZSH_CONFIG_PATH:-$HOME/setup/dotfiles/zsh}"

if command -v gcloud &>/dev/null; then
	source "$ZSH_CONFIG_PATH/plugins/.fzf-gcloud.plugin.zsh"
fi
