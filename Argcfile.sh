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
# @meta require-tools curl
setup::uv() {
	# uvのアップデートが早く、nix repositoryは最新版の反映が遅れる
	# devboxでインストールすると、`uv self update`で更新できない
	# そのため、curlでインストールする
	curl -LsSf https://astral.sh/uv/install.sh | sh
}

# @cmd setup bun
# @meta require-tools curl,unzip
setup::bun() {
	# bunのアップデートが早く、nix repositoryは最新版の反映が遅れる
	# そのため、curlでインストールする
	curl -fsSL https://bun.sh/install | bash
}

# @cmd setup volta
# @meta require-tools curl
setup::volta() {
	curl https://get.volta.sh | bash
}

# @cmd setup devbox
# @flag	-g	--global	setup devbox global
# @meta require-tools curl
setup::devbox() {
	# devboxがインストールされていない場合はインストールする
	if ! command -v devbox >/dev/null 2>&1; then
		curl -fsSL https://get.jetify.com/devbox | bash -s -- -f
	else
		echo "devbox is already installed"
	fi

	if [ "$argc_global" -eq 1 ]; then
		_argc_run setup devbox-global
	fi
}

# @cmd setup devbox global
# @meta require-tools curl,git,devbox
setup::devbox-global() {
	if ! (command -v git >/dev/null 2>&1 && command -v xz >/dev/null 2>&1); then
		echo "git or xz are not found. install them."
		exit 1
	fi

	# need curl, git, xz
	# apt update
	# apt install curl git xz-utils
	yes | devbox global pull https://github.com/Nishikoh/devbox.git
	eval "$(devbox global shellenv --preserve-path-stack -r)" && hash -r
}

# @cmd setup zsh login shell
setup::zsh-login() {
	# zshがインストールされていない場合はインストールする
	if ! command -v zsh >/dev/null 2>&1; then
		echo "zsh is not installed. installing..."
		devbox global add zsh
		eval "$(devbox global shellenv --preserve-path-stack -r)" && hash -r
	fi
	# zshをログインシェルに設定する
	chsh -s "$(which zsh)"
}

# @cmd setup rust and cargo
# @meta require-tools curl
setup::rust() {
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
# @meta require-tools cargo
setup::rust-bins() {
	_argc_run setup rust
	cargo install cargo-binstall
	cargo binstall cpz
	cargo binstall rmz
	cargo binstall xcp
}

# @cmd setup .config/ directory
# @arg path=~/setup/dotfiles 		path to git clone for dotfiles
setup::config() {
	cd "$argc_path"
	cp -r .config/ ~/.config/
}

# @cmd setup github copilot
# @alias gh-copilot
# @meta require-tools git,gh
setup::copilot() {

	if ! gh copilot --version; then
		gh auth login --web -h github.com
		gh extension install github/gh-copilot --force
	fi

	echo "Start Vim/Neovim and invoke ':Copilot setup' ."
	git clone https://github.com/github/copilot.vim.git \
		~/.vim/pack/github/start/copilot.vim
}

# @cmd setup binary from github releases
# @meta require-tools uvx,gh
setup::gh-bins() {

	if [ "$(uname)" == 'Darwin' ]; then
		# macだと依存関係の問題でエラーになる
		brew install libmagic
	fi
	uvx --with setuptools install-release config --token $(gh auth token)
	grep -v -e '^#' -e '^$' bin_github.txt | xargs -I {} uvx --with setuptools install-release get {} -y
}

# @cmd setup cuda
setup::cuda() {
	echo "TODO:"
	# TODO: setup CUDA
	# disable auto upgrade
}

link_targets_list=(".gitconfig" ".vimrc" ".zshrc")

# @cmd setup dotfiles
# @arg path=~/setup/dotfiles 		path to git clone for dotfiles
# @meta require-tools git
setup::dotfiles() {

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

# @cmd completion shell
# @arg path=~/setup/dotfiles 		path to git clone for dotfiles
# @meta require-tools git,argc
setup::completion() {
	# setup::dotfiles $argc_path
	argc_completions_path=~/setup/argc-completions
	if [ -d $argc_completions_path ]; then
		echo "skip git clone"
	else
		git clone https://github.com/sigoden/argc-completions.git $argc_completions_path
	fi
	cd $argc_completions_path
	./scripts/download-tools.sh

	argc generate git
	git restore completions/

	# lefthook wrapperの補完を追加
	cp completions/lefthook.sh completions/lh.sh
	# ${argc__args[0]} という文字列をlefthookに置き換える
	sed -i -e "s|\${argc__args\[0\]}|lefthook|g" completions/lh.sh

	./scripts/setup-shell.sh zsh
	cd -
}

# @cmd setup gcloud
setup::gcloud() {
	:
}

# @cmd setup gcloud fzf
setup::gcloud-fzf() {
	if ! [ -d "./zsh/plugins" ]; then
		echo "current directory is invalid. move parent './zsh/plugins' "
	else
		curl https://raw.githubusercontent.com/mbhynes/fzf-gcloud/main/fzf-gcloud.plugin.zsh >./zsh/plugins/.fzf-gcloud.plugin.zsh
		echo "download gcloud-fzf script"
	fi
}

# @cmd setup terraform-target with fzf
# @meta require-tools curl
setup::terraform-fzf() {
	if ! [ -d "$HOME/setup/bin" ]; then
		mkdir "$HOME"/setup/bin
	fi
	curl -o "$HOME"/setup/bin/terraform-target https://raw.githubusercontent.com/soar/terraform-target/refs/heads/main/terraform-target
	echo "download terraform-fzf script"
}

# @cmd Make setup easy.
#
# Selecting 'large' will take longer. Recommend not to use the 'large' option
# @flag  	--install-rust-bins	Install rust binaries
# @flag  	--install-gh-bins		Install gh binaries
lazy-setup() {

	_argc_run setup dotfiles
	_argc_run setup devbox
	_argc_run setup zsh-login
	_argc_run setup uv
	_argc_run setup bun
	_argc_run setup config
	_argc_run setup completion
	_argc_run setup rust

	if [ "$argc_install_gh_bins" -eq 1 ]; then
		echo "start gh binary"
		_argc_run setup copilot
		_argc_run setup gh-bins
		echo "finish gh binary"
	else
		echo "skip install gh binary"
	fi

	if [ "$argc_install_rust_bins" -eq 1 ]; then
		echo "start cargo binary"
		_argc_run setup rust-bins
		echo "finish cargo binary"
	else
		echo "skip install cargo binary"
	fi
}

_argc_run() {
	# setup:xxx のような実行の仕方だと、argcで設定したパラメータやフラグのデフォルトの値が無効になる
	# これを回避する為にargc経由で実行する必要があるが、　`--argc-build`で生成したスクリプトは`argc`バイナリに依存しない
	# 生成された`_argc_run`の関数がargcの代わりとなる。
	# ファイル生成する前のargcと生成した後の`_argc_run`の挙動を同じにするための関数
	# 生成したファイルではoverrideされる

	# echo debug
	argc "$@"
}

# See more details at https://github.com/sigoden/argc
eval "$(argc --argc-eval "$0" "$@")"
