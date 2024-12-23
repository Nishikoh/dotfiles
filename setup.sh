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
	cargo binstall cpz
	cargo binstall rmz
	cargo binstall xcp
}

# @cmd setup .config/ directory
setup::config() {
	cp -r .config/ ~/.config/
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

link_targets_list=(".gitconfig" ".vimrc" ".zshrc")

# @cmd setup dotfiles
# @arg path=~/setup/dotfiles 		path to git clone for dotfiles
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
	grep -v -e '^#' -e '^$' bin_github.txt | xargs -I {} uvx --with setuptools install-release get {} -y
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
# ARGC-BUILD {
# This block was generated by argc (https://github.com/sigoden/argc).
# Modifying it manually is not recommended

_argc_run() {
    if [[ "${1:-}" == "___internal___" ]]; then
        _argc_die "error: unsupported ___internal___ command"
    fi
    if [[ "${OS:-}" == "Windows_NT" ]] && [[ -n "${MSYSTEM:-}" ]]; then
        set -o igncr
    fi
    argc__args=("$(basename "$0" .sh)" "$@")
    argc__positionals=()
    _argc_index=1
    _argc_len="${#argc__args[@]}"
    _argc_tools=()
    _argc_parse
    if [ -n "${argc__fn:-}" ]; then
        $argc__fn "${argc__positionals[@]}"
    fi
}

_argc_usage() {
    cat <<-'EOF'
Setup environment and tools

USAGE: Argcfile <COMMAND>

COMMANDS:
  setup       setup each environments and each tools
  clean       unset environments and tools
  lazy-setup  Make setup easy.
EOF
    exit
}

_argc_version() {
    echo Argcfile 0.0.0
    exit
}

_argc_parse() {
    local _argc_key _argc_action
    local _argc_subcmds="setup, clean, lazy-setup"
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage
            ;;
        --version | -version | -V)
            _argc_version
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        setup)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup
            break
            ;;
        clean)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_clean
            break
            ;;
        lazy-setup)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_lazy-setup
            break
            ;;
        help)
            local help_arg="${argc__args[$((_argc_index + 1))]:-}"
            case "$help_arg" in
            setup)
                _argc_usage_setup
                ;;
            clean)
                _argc_usage_clean
                ;;
            lazy-setup)
                _argc_usage_lazy-setup
                ;;
            "")
                _argc_usage
                ;;
            *)
                _argc_die "error: invalid value \`$help_arg\` for \`<command>\`"$'\n'"  [possible values: $_argc_subcmds]"
                ;;
            esac
            ;;
        *)
            _argc_die "error: \`Argcfile\` requires a subcommand but one was not provided"$'\n'"  [subcommands: $_argc_subcmds]"
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        _argc_usage
    fi
}

_argc_usage_setup() {
    cat <<-'EOF'
setup each environments and each tools

USAGE: Argcfile setup <COMMAND>

COMMANDS:
  uv             setup uv
  devbox         setup devbox
  rust           setup rust and cargo
  config         setup .config/ directory
  copilot        setup github copilot [aliases: gh-copilot]
  cuda           setup cuda
  dotfiles       setup dotfiles
  completion     completion shell
  gcloud         setup gcloud
  terraform-fzf  setup terraform-target with fzf
  bin-gh         setup binary from github releases
EOF
    exit
}

_argc_parse_setup() {
    local _argc_key _argc_action
    local _argc_subcmds="uv, devbox, rust, config, copilot, gh-copilot, cuda, dotfiles, completion, gcloud, terraform-fzf, bin-gh"
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        uv)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_uv
            break
            ;;
        devbox)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_devbox
            break
            ;;
        rust)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_rust
            break
            ;;
        config)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_config
            break
            ;;
        copilot | gh-copilot)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_copilot
            break
            ;;
        cuda)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_cuda
            break
            ;;
        dotfiles)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_dotfiles
            break
            ;;
        completion)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_completion
            break
            ;;
        gcloud)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_gcloud
            break
            ;;
        terraform-fzf)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_terraform-fzf
            break
            ;;
        bin-gh)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_bin-gh
            break
            ;;
        help)
            local help_arg="${argc__args[$((_argc_index + 1))]:-}"
            case "$help_arg" in
            uv)
                _argc_usage_setup_uv
                ;;
            devbox)
                _argc_usage_setup_devbox
                ;;
            rust)
                _argc_usage_setup_rust
                ;;
            config)
                _argc_usage_setup_config
                ;;
            copilot | gh-copilot)
                _argc_usage_setup_copilot
                ;;
            cuda)
                _argc_usage_setup_cuda
                ;;
            dotfiles)
                _argc_usage_setup_dotfiles
                ;;
            completion)
                _argc_usage_setup_completion
                ;;
            gcloud)
                _argc_usage_setup_gcloud
                ;;
            terraform-fzf)
                _argc_usage_setup_terraform-fzf
                ;;
            bin-gh)
                _argc_usage_setup_bin-gh
                ;;
            "")
                _argc_usage_setup
                ;;
            *)
                _argc_die "error: invalid value \`$help_arg\` for \`<command>\`"$'\n'"  [possible values: $_argc_subcmds]"
                ;;
            esac
            ;;
        *)
            _argc_die "error: \`Argcfile-setup\` requires a subcommand but one was not provided"$'\n'"  [subcommands: $_argc_subcmds]"
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        _argc_usage_setup
    fi
}

_argc_usage_setup_uv() {
    cat <<-'EOF'
setup uv

USAGE: Argcfile setup uv
EOF
    exit
}

_argc_parse_setup_uv() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_uv
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::uv
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_uv
        fi
    fi
}

_argc_usage_setup_devbox() {
    cat <<-'EOF'
setup devbox

USAGE: Argcfile setup devbox
EOF
    exit
}

_argc_parse_setup_devbox() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_devbox
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::devbox
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_devbox
        fi
    fi
}

_argc_usage_setup_rust() {
    cat <<-'EOF'
setup rust and cargo

USAGE: Argcfile setup rust <COMMAND>

COMMANDS:
  install  setup rust and cargo [default]
  bins     install cargo binary. need some time.
EOF
    exit
}

_argc_parse_setup_rust() {
    local _argc_key _argc_action
    local _argc_subcmds="install, bins"
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_rust
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        install)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_rust_install
            break
            ;;
        bins)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_rust_bins
            break
            ;;
        help)
            local help_arg="${argc__args[$((_argc_index + 1))]:-}"
            case "$help_arg" in
            install)
                _argc_usage_setup_rust_install
                ;;
            bins)
                _argc_usage_setup_rust_bins
                ;;
            "")
                _argc_usage_setup_rust
                ;;
            *)
                _argc_die "error: invalid value \`$help_arg\` for \`<command>\`"$'\n'"  [possible values: $_argc_subcmds]"
                ;;
            esac
            ;;
        *)
            if [[ "${#argc__positionals[@]}" -eq 0 ]]; then
                _argc_action=_argc_parse_setup_rust_install
                break
            fi
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        _argc_usage_setup_rust
    fi
}

_argc_usage_setup_rust_install() {
    cat <<-'EOF'
setup rust and cargo

USAGE: Argcfile setup rust install
EOF
    exit
}

_argc_parse_setup_rust_install() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_rust_install
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::rust::install
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_rust_install
        fi
    fi
}

_argc_usage_setup_rust_bins() {
    cat <<-'EOF'
install cargo binary. need some time.

USAGE: Argcfile setup rust bins
EOF
    exit
}

_argc_parse_setup_rust_bins() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_rust_bins
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::rust::bins
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_rust_bins
        fi
    fi
}

_argc_usage_setup_config() {
    cat <<-'EOF'
setup .config/ directory

USAGE: Argcfile setup config
EOF
    exit
}

_argc_parse_setup_config() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_config
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::config
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_config
        fi
    fi
}

_argc_usage_setup_copilot() {
    cat <<-'EOF'
setup github copilot

USAGE: Argcfile setup copilot
EOF
    exit
}

_argc_parse_setup_copilot() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_copilot
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::copilot
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_copilot
        fi
    fi
}

_argc_usage_setup_cuda() {
    cat <<-'EOF'
setup cuda

USAGE: Argcfile setup cuda <COMMAND>

COMMANDS:
  install  [default]
EOF
    exit
}

_argc_parse_setup_cuda() {
    local _argc_key _argc_action
    local _argc_subcmds="install"
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_cuda
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        install)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_cuda_install
            break
            ;;
        help)
            local help_arg="${argc__args[$((_argc_index + 1))]:-}"
            case "$help_arg" in
            install)
                _argc_usage_setup_cuda_install
                ;;
            "")
                _argc_usage_setup_cuda
                ;;
            *)
                _argc_die "error: invalid value \`$help_arg\` for \`<command>\`"$'\n'"  [possible values: $_argc_subcmds]"
                ;;
            esac
            ;;
        *)
            if [[ "${#argc__positionals[@]}" -eq 0 ]]; then
                _argc_action=_argc_parse_setup_cuda_install
                break
            fi
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        _argc_usage_setup_cuda
    fi
}

_argc_usage_setup_cuda_install() {
    cat <<-'EOF'
USAGE: Argcfile setup cuda install
EOF
    exit
}

_argc_parse_setup_cuda_install() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_cuda_install
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::cuda::install
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_cuda_install
        fi
    fi
}

_argc_usage_setup_dotfiles() {
    cat <<-'EOF'
setup dotfiles

USAGE: Argcfile setup dotfiles [PATH]

ARGS:
  [PATH]  path to git clone for dotfiles [default: ~/setup/dotfiles]
EOF
    exit
}

_argc_parse_setup_dotfiles() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_dotfiles
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::dotfiles
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_dotfiles
        fi
        _argc_match_positionals 0
        local values_index values_size
        IFS=: read -r values_index values_size <<<"${_argc_match_positionals_values[0]:-}"
        if [[ -n "$values_index" ]]; then
            argc_path="${argc__positionals[values_index]}"
        else
            argc_path=~/setup/dotfiles
            argc__positionals+=("$argc_path")
        fi
    fi
}

_argc_usage_setup_completion() {
    cat <<-'EOF'
completion shell

USAGE: Argcfile setup completion [PATH]

ARGS:
  [PATH]  path to git clone for dotfiles [default: ~/setup/dotfiles]
EOF
    exit
}

_argc_parse_setup_completion() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_completion
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::completion
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_completion
        fi
        _argc_match_positionals 0
        local values_index values_size
        IFS=: read -r values_index values_size <<<"${_argc_match_positionals_values[0]:-}"
        if [[ -n "$values_index" ]]; then
            argc_path="${argc__positionals[values_index]}"
        else
            argc_path=~/setup/dotfiles
            argc__positionals+=("$argc_path")
        fi
    fi
}

_argc_usage_setup_gcloud() {
    cat <<-'EOF'
setup gcloud

USAGE: Argcfile setup gcloud <COMMAND>

COMMANDS:
  install  setup gcloud cli
  fzf      setup gcloud fzf
EOF
    exit
}

_argc_parse_setup_gcloud() {
    local _argc_key _argc_action
    local _argc_subcmds="install, fzf"
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_gcloud
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        install)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_gcloud_install
            break
            ;;
        fzf)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_setup_gcloud_fzf
            break
            ;;
        help)
            local help_arg="${argc__args[$((_argc_index + 1))]:-}"
            case "$help_arg" in
            install)
                _argc_usage_setup_gcloud_install
                ;;
            fzf)
                _argc_usage_setup_gcloud_fzf
                ;;
            "")
                _argc_usage_setup_gcloud
                ;;
            *)
                _argc_die "error: invalid value \`$help_arg\` for \`<command>\`"$'\n'"  [possible values: $_argc_subcmds]"
                ;;
            esac
            ;;
        *)
            _argc_die "error: \`Argcfile-setup-gcloud\` requires a subcommand but one was not provided"$'\n'"  [subcommands: $_argc_subcmds]"
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        _argc_usage_setup_gcloud
    fi
}

_argc_usage_setup_gcloud_install() {
    cat <<-'EOF'
setup gcloud cli

USAGE: Argcfile setup gcloud install
EOF
    exit
}

_argc_parse_setup_gcloud_install() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_gcloud_install
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::gcloud::install
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_gcloud_install
        fi
    fi
}

_argc_usage_setup_gcloud_fzf() {
    cat <<-'EOF'
setup gcloud fzf

USAGE: Argcfile setup gcloud fzf
EOF
    exit
}

_argc_parse_setup_gcloud_fzf() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_gcloud_fzf
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::gcloud::fzf
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_gcloud_fzf
        fi
    fi
}

_argc_usage_setup_terraform-fzf() {
    cat <<-'EOF'
setup terraform-target with fzf

USAGE: Argcfile setup terraform-fzf
EOF
    exit
}

_argc_parse_setup_terraform-fzf() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_terraform-fzf
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::terraform-fzf
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_terraform-fzf
        fi
    fi
}

_argc_usage_setup_bin-gh() {
    cat <<-'EOF'
setup binary from github releases

USAGE: Argcfile setup bin-gh
EOF
    exit
}

_argc_parse_setup_bin-gh() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_setup_bin-gh
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=setup::bin-gh
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_setup_bin-gh
        fi
    fi
}

_argc_usage_clean() {
    cat <<-'EOF'
unset environments and tools

USAGE: Argcfile clean <COMMAND>

COMMANDS:
  dotfiles  unset dotfiles
EOF
    exit
}

_argc_parse_clean() {
    local _argc_key _argc_action
    local _argc_subcmds="dotfiles"
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_clean
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        dotfiles)
            _argc_index=$((_argc_index + 1))
            _argc_action=_argc_parse_clean_dotfiles
            break
            ;;
        help)
            local help_arg="${argc__args[$((_argc_index + 1))]:-}"
            case "$help_arg" in
            dotfiles)
                _argc_usage_clean_dotfiles
                ;;
            "")
                _argc_usage_clean
                ;;
            *)
                _argc_die "error: invalid value \`$help_arg\` for \`<command>\`"$'\n'"  [possible values: $_argc_subcmds]"
                ;;
            esac
            ;;
        *)
            _argc_die "error: \`Argcfile-clean\` requires a subcommand but one was not provided"$'\n'"  [subcommands: $_argc_subcmds]"
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        _argc_usage_clean
    fi
}

_argc_usage_clean_dotfiles() {
    cat <<-'EOF'
unset dotfiles

USAGE: Argcfile clean dotfiles
EOF
    exit
}

_argc_parse_clean_dotfiles() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_clean_dotfiles
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        *)
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=clean::dotfiles
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_clean_dotfiles
        fi
    fi
}

_argc_usage_lazy-setup() {
    cat <<-'EOF'
Make setup easy.

Selecting 'large' will take longer. Recommend not to use the 'large' option

USAGE: Argcfile lazy-setup [OPTIONS]

OPTIONS:
  -l, --large  It takes a long time by 'cargo install'
  -h, --help   Print help
EOF
    exit
}

_argc_parse_lazy-setup() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage_lazy-setup
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        --large | -l)
            if [[ "$_argc_item" == *=* ]]; then
                _argc_die "error: flag \`--large\` don't accept any value"
            fi
            _argc_index=$((_argc_index + 1))
            if [[ -n "${argc_large:-}" ]]; then
                _argc_die "error: the argument \`--large\` cannot be used multiple times"
            else
                argc_large=1
            fi
            ;;
        *)
            if _argc_maybe_flag_option "-" "$_argc_item"; then
                _argc_die "error: unexpected argument \`$_argc_key\` found"
            fi
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=lazy-setup
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage_lazy-setup
        fi
    fi
}

_argc_match_positionals() {
    _argc_match_positionals_values=()
    _argc_match_positionals_len=0
    local params=("$@")
    local args_len="${#argc__positionals[@]}"
    if [[ $args_len -eq 0 ]]; then
        return
    fi
    local params_len=$# arg_index=0 param_index=0
    while [[ $param_index -lt $params_len && $arg_index -lt $args_len ]]; do
        local takes=0
        if [[ "${params[param_index]}" -eq 1 ]]; then
            if [[ $param_index -eq 0 ]] &&
                [[ ${_argc_dash:-} -gt 0 ]] &&
                [[ $params_len -eq 2 ]] &&
                [[ "${params[$((param_index + 1))]}" -eq 1 ]] \
                ; then
                takes=${_argc_dash:-}
            else
                local arg_diff=$((args_len - arg_index)) param_diff=$((params_len - param_index))
                if [[ $arg_diff -gt $param_diff ]]; then
                    takes=$((arg_diff - param_diff + 1))
                else
                    takes=1
                fi
            fi
        else
            takes=1
        fi
        _argc_match_positionals_values+=("$arg_index:$takes")
        arg_index=$((arg_index + takes))
        param_index=$((param_index + 1))
    done
    if [[ $arg_index -lt $args_len ]]; then
        _argc_match_positionals_values+=("$arg_index:$((args_len - arg_index))")
    fi
    _argc_match_positionals_len=${#_argc_match_positionals_values[@]}
    if [[ $params_len -gt 0 ]] && [[ $_argc_match_positionals_len -gt $params_len ]]; then
        local index="${_argc_match_positionals_values[params_len]%%:*}"
        _argc_die "error: unexpected argument \`${argc__positionals[index]}\` found"
    fi
}

_argc_maybe_flag_option() {
    local signs="$1" arg="$2"
    if [[ -z "$signs" ]]; then
        return 1
    fi
    local cond=false
    if [[ "$signs" == *"+"* ]]; then
        if [[ "$arg" =~ ^\+[^+].* ]]; then
            cond=true
        fi
    elif [[ "$arg" == -* ]]; then
        if (( ${#arg} < 3 )) || [[ ! "$arg" =~ ^---.* ]]; then
            cond=true
        fi
    fi
    if [[ "$cond" == "false" ]]; then
        return 1
    fi
    local value="${arg%%=*}"
    if [[ "$value" =~ [[:space:]] ]]; then
        return 1
    fi
    return 0
}

_argc_die() {
    if [[ $# -eq 0 ]]; then
        cat
    else
        echo "$*" >&2
    fi
    exit 1
}

_argc_run "$@"

# ARGC-BUILD }
