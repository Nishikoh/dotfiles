#!/usr/bin/env bash
# -*- coding: utf-8 -*-

set -e

# @describe Setup environment and tools

# @cmd setup environments and tools
setup() {
	:
}

# @cmd unset environments and tools
clean() {
	:
}

# @cmd setup devbox
setup::devbox() {
	# devboxがインストールされていない場合はインストールする
	if ! command -v devbox 2>&1 >/dev/null; then
		curl -fsSL https://get.jetify.com/devbox | bash -s -- -f
	else
		echo "devbox is already installed"
	fi

    if ! (command -v git 2>&1 >/dev/null && command -v xz 2>&1 >/dev/null); then
        echo "git or xz are not found. install them."
        exit 1
    fi


    # need curl, git, xz
    # apt update
    # apt install curl git xz-utils
	yes | devbox global pull https://github.com/Nishikoh/devbox.git
    eval "$(devbox global shellenv)"
}

# @cmd completion shell
setup::completion() {
	git clone https://github.com/sigoden/argc-completions.git
	cd argc-completions
	./scripts/download-tools.sh
	./scripts/setup-shell.sh zsh
	cd -
}

# @cmd setup rust and cargo
setup::rust() {
	:
}

# @cmd setup rust and cargo
# @meta default-subcommand
setup::rust::install() {
	# rustがインストールされていない場合はインストールする
	if ! command -v cargo 2>&1 >/dev/null; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	else
		echo "rust is already installed"
	fi
}

# @cmd install cargo binary. need some time.
setup::rust::bins() {
	setup::rust::install
	cargo install cargo-binstall
	cargo binstall cpz
	cargo binstall rmz
	cargo binstall xcp
}

# @cmd setup github copilot
# @alias gh-copilot
setup::copilot() {

	if ! gh copilot --version; then
		gh auth login --web -h github.com
		gh extension install github/gh-copilot --force
	fi

	echo "Start Vim/Neovim and invoke :Copilot setup."
	git clone https://github.com/github/copilot.vim.git \
		~/.vim/pack/github/start/copilot.vim
}

# @cmd setup environments and tools quickly.
setup::slim() {
	setup::devbox
	setup::completion
	setup::copilot
}

# @cmd setup full environments and tools. need some time.
setup::full() {
	setup::slim
	setup::rust::bins
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

link_targets_list=(".gitconfig" ".vimrc" ".zshrc")

# @cmd setup dotfiles
setup::dotfiles() {

	cwd=$(dirname "${0}")
	ORIGINAL_DOTFILES_PATH=$( (cd "${cwd}" && pwd))
	ZSH_CONFIG_DIR=$ORIGINAL_DOTFILES_PATH/zsh

	if [ -d "$ZSH_CONFIG_DIR" ]; then
		ls "$ZSH_CONFIG_DIR"
	else
		echo zsh dir is not exists.
		exit 1
	fi

	if [ "$ORIGINAL_DOTFILES_PATH" = "$HOME" ]; then
		echo invalid dir. This is Home.
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

# See more details at https://github.com/sigoden/argc
eval "$(argc --argc-eval "$0" "$@")"
