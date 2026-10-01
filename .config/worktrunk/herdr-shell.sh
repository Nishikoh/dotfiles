# shellcheck shell=bash
# Herdr の pane では、wt の cd を移動先の worktree の workspace への focus に置き換える。
# 1 つの worktree を 1 つの workspace に対応させ、別の workspace の pane に checkout を持ち込まない。
# `wt config shell init` の後に source する (zsh / bash 共通)。
# Herdr が未起動、bare repo、操作元と同じ workspace 内の移動などで focus できない場合は通常どおり cd する。
if [[ -n ${HERDR_PANE_ID:-} && -f $HOME/.config/worktrunk/herdr-hook.sh ]]; then
	wt() {
		# 補完は wt 本体を直接呼ぶ (Worktrunk の shell integration と同じ)。
		if [[ -n ${COMPLETE:-} ]]; then
			command "${WORKTRUNK_BIN:-wt}" "$@"
			return
		fi
		local cd_file target exit_code=0 cd_exit=0
		cd_file=$(mktemp) || return
		WORKTRUNK_DIRECTIVE_CD_FILE=$cd_file command "${WORKTRUNK_BIN:-wt}" "$@" || exit_code=$?
		if [[ -s $cd_file ]]; then
			target=$(<"$cd_file")
			if ! bash "$HOME/.config/worktrunk/herdr-hook.sh" focus "$target"; then
				builtin cd -- "$target" || cd_exit=$?
				[[ $exit_code != 0 ]] || exit_code=$cd_exit
			fi
		fi
		command rm -f -- "$cd_file"
		return "$exit_code"
	}
fi
