# -----------------------------
# Plugins
# -----------------------------

# zsh設定ディレクトリのパス
ZSH_CONFIG_PATH="${ZSH_CONFIG_PATH:-$HOME/setup/dotfiles/zsh}"

if command -v gcloud &>/dev/null; then
	source "$ZSH_CONFIG_PATH/plugins/.fzf-gcloud.plugin.zsh"
fi

# zsh-helix-mode
# ZSH_HELIX_MODE_DISABLE=1 で無効化可能
if [[ -z "$ZSH_HELIX_MODE_DISABLE" ]]; then
	ZHM_DIR="$ZSH_CONFIG_PATH/plugins/zsh-helix-mode"
	if [[ ! -d "$ZHM_DIR" ]]; then
		echo "Installing zsh-helix-mode..."
		git clone --depth 1 https://github.com/Multirious/zsh-helix-mode "$ZHM_DIR"
	fi
	# macOS clipboard settings
	if [[ "$OSTYPE" == darwin* ]]; then
		export ZHM_CLIPBOARD_PIPE_CONTENT_TO="pbcopy"
		export ZHM_CLIPBOARD_READ_CONTENT_FROM="pbpaste"
	fi
	source "$ZHM_DIR/zsh-helix-mode.plugin.zsh"
fi
