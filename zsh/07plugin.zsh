# -----------------------------
# Plugins
# -----------------------------

# zsh設定ディレクトリのパス
ZSH_CONFIG_PATH="${ZSH_CONFIG_PATH:-$HOME/setup/dotfiles/zsh}"

# gcloud は lazy (.config/mise/mise.toml) なので、入る前から mise の shim が PATH にある。shim しか無いときは読み込まない
# (読むと、使わないマシンでも関数とキーの割り当てが入る。プラグインは gcloud の実体の場所からドキュメントを探すので、shim では使えない)。
# mise activate が .zshrc の途中で PATH を整えるので、入った後は実体が shim より先に見つかる
if [[ -n "${commands[gcloud]}" && "${commands[gcloud]}" != "${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims/gcloud" ]]; then
	source "$ZSH_CONFIG_PATH/plugins/.fzf-gcloud.plugin.zsh"
fi

# zsh-helix-mode
# ZSH_HELIX_MODE_DISABLE=1 で無効化可能
if [[ -z "$ZSH_HELIX_MODE_DISABLE" ]]; then
	ZHM_DIR="$ZSH_CONFIG_PATH/plugins/zsh-helix-mode"
	if [[ ! -d "$ZHM_DIR" ]]; then
		echo "Installing zsh-helix-mode..."
		git clone -b fix-utf-8-handling --depth 1 https://github.com/Nishikoh/zsh-helix-mode.git "$ZHM_DIR"
	fi
	# macOS clipboard settings
	if [[ "$OSTYPE" == darwin* ]]; then
		export ZHM_CLIPBOARD_PIPE_CONTENT_TO="pbcopy"
		export ZHM_CLIPBOARD_READ_CONTENT_FROM="pbpaste"
	fi
	source "$ZHM_DIR/zsh-helix-mode.plugin.zsh"
fi
