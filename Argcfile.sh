#!/usr/bin/env bash
# -*- coding: utf-8 -*-

set -e

# @describe Setup environment and tools

# @cmd setup each environments and each tools
setup() {
	:
}

# @cmd unset environments and tools
clean() {
	:
}

# @cmd setup uv
setup::uv() {
	# uvのアップデートが早く、nix repositoryは最新版の反映が遅れる
	# devboxでインストールすると、`uv self update`で更新できない
	# そのため、curlでインストールする
	curl -LsSf https://astral.sh/uv/install.sh | sh
}

# @cmd setup devbox
setup::devbox() {
	# devboxがインストールされていない場合はインストールする
	if ! command -v devbox >/dev/null 2>&1; then
		curl -fsSL https://get.jetify.com/devbox | bash -s -- -f
	else
		echo "devbox is already installed"
	fi

	if ! (command -v git >/dev/null 2>&1 && command -v xz >/dev/null 2>&1); then
		echo "git or xz are not found. install them."
		exit 1
	fi

	# need curl, git, xz
	# apt update
	# apt install curl git xz-utils
	yes | devbox global pull https://github.com/Nishikoh/devbox.git
	eval "$(devbox global shellenv)"
}

# @cmd setup rust and cargo
setup::rust() {
	:
}

# @cmd setup rust and cargo
# @meta default-subcommand
setup::rust::install() {
	# rustがインストールされていない場合はインストールする
	if ! command -v cargo >/dev/null 2>&1; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	else
		echo "rust is already installed"
		rustup update
		rustup self update
	fi
}

# @cmd install cargo binary. need some time.
setup::rust::bins() {
	setup::rust::install
	cargo install cargo-binstall
	cargo binstall cpz rmz xcp
}

# @cmd setup .config/ directory
# @arg path=~/setup/dotfiles 		path to dotfiles directory
setup::config() {
	# argcは @arg のデフォルト値をチルダ展開しないため、先頭の ~ を $HOME に展開する
	argc_path="${argc_path/#\~/$HOME}"
	# 優先順位: 引数 > 環境変数 > スクリプトの場所 > デフォルト
	if [ -n "$argc_path" ] && [ "$argc_path" != "$HOME/setup/dotfiles" ]; then
		DOTFILES_DIR="$argc_path"
	elif [ -n "$DOTFILES_DIR" ]; then
		: # DOTFILES_DIR is already set from environment
	elif [ -f "$0" ]; then
		DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
	else
		DOTFILES_DIR="$HOME/setup/dotfiles"
	fi

	SRC_DIR="$DOTFILES_DIR/.config"

	if [ ! -d "$SRC_DIR" ]; then
		echo "エラー: $SRC_DIR が存在しません"
		echo "ヒント: DOTFILES_DIR 環境変数を設定するか、引数でパスを指定してください"
		echo "  例: DOTFILES_DIR=/path/to/dotfiles curl ... | bash"
		echo "  例: argc setup::config /path/to/dotfiles"
		exit 1
	fi

	# ホームディレクトリの .config
	DEST_DIR="$HOME/.config"
	
	# DEST_DIR が存在しなければ作成
	mkdir -p "$DEST_DIR"
	
	# SRC_DIR 配下の全てのアイテムをループ
	for item in "$SRC_DIR"/*; do
	    # ベースネームだけ取り出す
	    name=$(basename "$item")
	    # シンボリックリンク先
	    link="$DEST_DIR/$name"
	
	    # 既にリンクやファイルが存在する場合はスキップ (リンク切れのシンボリックリンクも含む)
	    if [ -e "$link" ] || [ -L "$link" ]; then
	        echo "スキップ: $link は既に存在します"
	    else
	        ln -s "$item" "$link"
	        echo "リンク作成: $link -> $item"
	    fi
	done
}

# @cmd setup github copilot
# @alias gh-copilot
setup::copilot() {

	if ! gh copilot --version; then
		gh auth login --web -h github.com
		gh extension install github/gh-copilot --force
	fi

	echo "Start Vim/Neovim and invoke ':Copilot setup' ."
	git clone https://github.com/github/copilot.vim.git \
		~/.vim/pack/github/start/copilot.vim
}

# @cmd setup cuda
setup::cuda() {
	echo "TODO:"
	# TODO: setup CUDA
	# disable auto upgrade
}

# @cmd
# @meta default-subcommand
setup::cuda::install() {
	echo "TODO: install CUDA"
}

# TODO: mise対応
link_targets_list=(".gitconfig" ".vimrc" ".zshrc")

# ~/.claude 配下にsymlinkするアイテム (.claude/ からの相対パス)
claude_link_targets_list=("settings.json" "hooks" "statusline-command.sh" "skills/dev-lsp")

# @cmd setup dotfiles
# @arg path=~/setup/dotfiles 		path to git clone for dotfiles
setup::dotfiles() {
	# argcは @arg のデフォルト値をチルダ展開しないため、先頭の ~ を $HOME に展開する
	argc_path="${argc_path/#\~/$HOME}"

	if [ "$argc_path" = "$HOME" ]; then
		echo invalid dir. This is Home.
		exit 1
	fi

	if [ -d "$argc_path" ]; then
		echo "skip git clone"
	else
		git clone https://github.com/Nishikoh/dotfiles.git "${argc_path}"
	fi

	ORIGINAL_DOTFILES_PATH=$( (cd "${argc_path}" && pwd))
	ZSH_CONFIG_DIR=$ORIGINAL_DOTFILES_PATH/zsh

	if [ -d "$ZSH_CONFIG_DIR" ]; then
		ls "$ZSH_CONFIG_DIR"
	else
		echo zsh dir is not exists.
		exit 1
	fi

	for f in "${link_targets_list[@]}"; do
		if [[ -e "${ORIGINAL_DOTFILES_PATH}/${f}" ]]; then
			if [[ ! -e "${HOME}/${f}" ]] || diff -u "${ORIGINAL_DOTFILES_PATH}/${f}" "${HOME}/${f}"; then
				ln -snfv "${ORIGINAL_DOTFILES_PATH}/${f}" "${HOME}/${f}"
				echo link: "${f}"
			fi
		fi
	done
}

# @cmd unset dotfiles
clean::dotfiles() {
	for f in "${link_targets_list[@]}"; do
		if [ -L ~/"${f}" ]; then
			echo "$f"
			unlink ~/"${f}"
		fi
	done
}

# @cmd setup ~/.claude symlinks (settings.json/hooks/statusline-command.sh/skills/dev-lsp)
# @arg path=~/setup/dotfiles 		path to dotfiles directory
setup::claude() {
	# argcは @arg のデフォルト値をチルダ展開しないため、先頭の ~ を $HOME に展開する
	argc_path="${argc_path/#\~/$HOME}"
	# 優先順位: 引数 > 環境変数 > スクリプトの場所 > デフォルト
	if [ -n "$argc_path" ] && [ "$argc_path" != "$HOME/setup/dotfiles" ]; then
		DOTFILES_DIR="$argc_path"
	elif [ -n "$DOTFILES_DIR" ]; then
		: # DOTFILES_DIR is already set from environment
	elif [ -f "$0" ]; then
		DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
	else
		DOTFILES_DIR="$HOME/setup/dotfiles"
	fi

	SRC_DIR="$DOTFILES_DIR/.claude"

	if [ ! -d "$SRC_DIR" ]; then
		echo "エラー: $SRC_DIR が存在しません"
		exit 1
	fi

	# ln -f は非空の実ディレクトリを置き換えられない(中にリンクを作ってしまう)ため、
	# 既存が real file/dir の場合は diff で内容一致を確認してから rm -rf → ln -s する
	for f in "${claude_link_targets_list[@]}"; do
		src="$SRC_DIR/$f"
		dest="$HOME/.claude/$f"

		if [ ! -e "$src" ]; then
			echo "スキップ: $src が存在しません"
			continue
		fi

		if [ -L "$dest" ]; then
			rm "$dest"
		elif [ -e "$dest" ]; then
			if diff -ru "$src" "$dest"; then
				rm -rf "$dest"
			else
				echo "スキップ: $dest は内容が異なるため上書きしません"
				continue
			fi
		fi

		mkdir -p "$(dirname "$dest")"
		ln -s "$src" "$dest"
		echo "リンク作成: $dest -> $src"
	done
}

# @cmd unset ~/.claude symlinks
clean::claude() {
	for f in "${claude_link_targets_list[@]}"; do
		dest="$HOME/.claude/$f"
		if [ -L "$dest" ]; then
			echo "$f"
			unlink "$dest"
		fi
	done
}

# @cmd completion shell
# @arg path=~/setup/dotfiles 		path to git clone for dotfiles
setup::completion() {
	# setup::dotfiles $argc_path
	argc_completions_path=~/setup/argc-completions
	if [ -d $argc_completions_path ]; then
		echo "skip git clone"
	else
		git clone https://github.com/sigoden/argc-completions.git $argc_completions_path
	fi
	(
		cd "$argc_completions_path" || exit 1
		./scripts/download-tools.sh

		argc generate git
		git restore completions/

		# lefthook wrapperの補完を追加
		cp completions/lefthook.sh completions/lh.sh
		# ${argc__args[0]} という文字列をlefthookに置き換える
		sed -i -e "s|\${argc__args\[0\]}|lefthook|g" completions/lh.sh

		./scripts/setup-shell.sh zsh
	)
}

# @cmd setup gcloud
setup::gcloud() {
	:
}

# @cmd setup gcloud cli
setup::gcloud::install() {
	# TODO
	:
}

# @cmd setup gcloud fzf
setup::gcloud::fzf() {
	if ! [ -d "./zsh/plugins" ]; then
		echo "current directory is invalid. move parent './zsh/plugins' "
	else
		curl https://raw.githubusercontent.com/mbhynes/fzf-gcloud/main/fzf-gcloud.plugin.zsh >./zsh/plugins/.fzf-gcloud.plugin.zsh
		echo "download gcloud-fzf script"
	fi
}

# @cmd setup terraform-target with fzf
setup::terraform-fzf() {
	if ! [ -d "$HOME/setup/bin" ]; then
		mkdir "$HOME"/setup/bin
	fi
	curl -o "$HOME"/setup/bin/terraform-target https://raw.githubusercontent.com/soar/terraform-target/refs/heads/main/terraform-target
	echo "download terraform-fzf script"
}

# @cmd setup binary from github releases
setup::bin-gh() {

	if [ "$(uname)" == 'Darwin' ]; then
		# macだと依存関係の問題でエラーになる
		brew install libmagic
	fi
	grep -v -e '^#' -e '^$' bin_github.txt | xargs -P 4 -I {} uvx --with setuptools install-release get {} -y
}

# @cmd Make setup easy.
#
# Selecting 'large' will take longer. Recommend not to use the 'large' option
# @flag  	-l		--large      					It takes a long time by 'cargo install'
lazy-setup() {

	setup::devbox
	setup::dotfiles
	setup::uv
	setup::config
	setup::completion
	setup::rust
	setup::copilot
	setup::bin-gh

	if [ "$argc_large" -eq 1 ]; then
		echo "start cargo binary"
		setup::rust::bins
		echo "finish cargo binary"
	else
		echo "skip install cargo binary"
	fi
}

# See more details at https://github.com/sigoden/argc
eval "$(argc --argc-eval "$0" "$@")"
