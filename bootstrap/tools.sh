#!/usr/bin/env bash
# このマシンで外すツール (mise の disable_tools) を表示・変更する。mise.toml の tools:* タスクと final hook から呼ぶ。
#
#   tools.sh status                          外しているツールと、その設定元を表示する
#   tools.sh summary                         外しているツールを 1 行で表示する (bootstrap の最後に表示する)
#   tools.sh disable [tool...]               外してアンインストールする。省略すると fzf で選ぶ
#   tools.sh enable [--no-install] [tool...] 戻してインストールする。省略すると fzf で選ぶ
#
# 既定では .config/mise/config.toml の disable_tools (プリセット) を外す。マシンごとの値は
# ~/.config/mise/config.local.toml (git に無視される) に書く。mise ではこの値がプリセットに足されず置き換わるので、
# 今の値にツールを足したり引いたりした全体を書く。
# `mise config set` は空のリストを書けない (--remove で空にするとキーごと消えてプリセットに戻る) ので、行を直接書き換える。
set -euo pipefail

config_dir="${HOME}/.config/mise"
preset_file="${config_dir}/config.toml"
local_file="${config_dir}/config.local.toml"

# グローバルの設定だけを見る。リポジトリの別のチェックアウトの中ではそのチェックアウトの設定が優先され、
# その実行だけの MISE_DISABLE_TOOLS なども効いてしまうため
global_mise() {
	(cd / && env -u MISE_DISABLE_TOOLS -u MISE_ENABLE_TOOLS mise "$@")
}

# mise の表示 (["a", "b"]) を 1 行に 1 つにする
to_lines() {
	sed -e 's/[][" ]//g' -e 's/,/\n/g' | sed '/^$/d'
}

disabled_tools() {
	global_mise settings get disable_tools | to_lines
}

# 外しているツールを配列 current に読み込む。mise が失敗したら止まる (プロセス置換では失敗が伝わらず、
# 空のリストとして書き込んでしまうため)
read_current() {
	local out
	out="$(disabled_tools)"
	current=()
	if [[ -n "${out}" ]]; then
		mapfile -t current <<<"${out}"
	fi
}

# グローバルの設定にあるツール (外しているものを含む)
configured_tools() {
	global_mise config ls --no-header --no-truncate | sed -E 's/^[^ ]+ +//' | grep -vxF '(none)' | sed 's/, /\n/g' | sort -u
}

has_local_setting() {
	[[ -f "${local_file}" ]] && global_mise config get -f "${local_file}" settings.disable_tools >/dev/null 2>&1
}

# プリセット (.config/mise/config.toml の disable_tools) を名前順に出力する
preset_tools() {
	if grep -qE '^[[:space:]]*disable_tools[[:space:]]*=' "${preset_file}" 2>/dev/null; then
		global_mise config get -f "${preset_file}" settings.disable_tools | to_lines | LC_ALL=C sort -u
	fi
}

# ~/.config/mise/config.local.toml の disable_tools を引数のツールで置き換える (ファイルのほかの内容は残す)。
# プリセットと同じになるときは disable_tools を消してプリセットに従わせる。プリセットのコピーを持つと、
# あとでプリセットを変えてもこのマシンに反映されないため
write_disabled_tools() {
	local line=""
	if [[ "$(printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort -u)" != "$(preset_tools)" ]]; then
		local value=""
		local tool
		for tool in "$@"; do
			value+="${value:+, }\"${tool}\""
		done
		line="disable_tools = [${value}]"
	elif ! has_local_setting; then
		return 0
	fi
	touch "${local_file}"
	local tmp
	tmp="$(mktemp "${local_file}.XXXXXX")"
	awk -v line="${line}" '
		# 既存の disable_tools (複数行の配列を含む) は捨てて、書くときは [settings] の直後に書く
		skip { if (/\]/) skip = 0; next }
		/^[[:space:]]*disable_tools[[:space:]]*=/ { if ($0 !~ /\]/) skip = 1; next }
		{ print }
		line != "" && /^[[:space:]]*\[settings\][[:space:]]*$/ && !done { print line; done = 1 }
		END {
			if (line != "" && !done) {
				if (NR > 0) print ""
				print "[settings]"
				print line
			}
		}
	' "${local_file}" >"${tmp}"
	# [settings] しか残らなければ (タスクが作ったファイル)、ファイルごと消す
	if grep -qvE '^[[:space:]]*(\[settings\][[:space:]]*)?$' "${tmp}"; then
		mv "${tmp}" "${local_file}"
	else
		rm -f "${tmp}" "${local_file}"
	fi
	if [[ -z "${line}" ]]; then
		echo "プリセットと同じになったので、このマシンの設定を消しました (以後はプリセットに従います)"
	fi
}

# 標準入力の候補から fzf で複数選び、選んだものを出力する。
# fzf --multi は何も選ばずに ENTER を押すとカーソル行を返すので、bin/mise-install-missing と同じく
# TAB で選んだものを自分でファイルに記録し、ENTER ではそのファイルの内容を結果にする
select_with_fzf() {
	local header="$1"
	local selected_file
	selected_file="$(mktemp)"
	# shellcheck disable=SC2016 # {} と $item は fzf が実行するシェルで展開する
	fzf --multi \
		--header="${header} (TAB で選択、ENTER で決定)" \
		--bind 'tab:toggle+execute-silent(
			item={};
			if grep -qxF "$item" '"${selected_file}"' 2>/dev/null; then
				grep -vxF "$item" '"${selected_file}"' > '"${selected_file}"'.tmp;
				mv '"${selected_file}"'.tmp '"${selected_file}"';
			else
				echo "$item" >> '"${selected_file}"';
			fi
		)+down' \
		--bind 'enter:abort' >/dev/null || true
	cat "${selected_file}"
	rm -f "${selected_file}" "${selected_file}.tmp"
}

# 引数を省いたときに fzf で選ぶ。入力が端末でなければ選べないので失敗する (fzf の画面は /dev/tty に出るので、出力は端末でなくてよい)
require_fzf() {
	if [[ ! -t 0 ]] || ! command -v fzf >/dev/null; then
		echo "ツールを引数で指定してください (fzf で選べるのは端末から実行したときだけ)" >&2
		return 1
	fi
}

join_list() {
	paste -sd, - | sed 's/,/, /g'
}

cmd_status() {
	local disabled here
	disabled="$(disabled_tools | join_list)"
	echo "外しているツール: ${disabled:-なし}"
	if has_local_setting; then
		echo "  設定元: このマシン (${local_file})"
	else
		echo "  設定元: プリセット (${preset_file})"
	fi
	# リポジトリの別のチェックアウト (worktree) の中では、そのチェックアウトの設定がプロジェクトの設定として優先される
	here="$(env -u MISE_DISABLE_TOOLS -u MISE_ENABLE_TOOLS mise settings get disable_tools | to_lines | join_list)"
	if [[ "${here}" != "${disabled}" ]]; then
		echo "  ただし ${PWD} の中では、そのチェックアウトの設定が優先され、外しているツール: ${here:-なし}"
	fi
	echo "変更: mise run tools:disable [tool...] / mise run tools:enable [tool...] (引数を省くと fzf で選ぶ)"
}

cmd_summary() {
	local disabled
	disabled="$(disabled_tools 2>/dev/null | join_list)" || return 0
	if [[ -n "${disabled}" ]]; then
		echo "外しているツール: ${disabled} (戻すときは mise run tools:enable)"
	fi
}

cmd_disable() {
	local current configured
	read_current
	configured="$(configured_tools)"
	local tools=("$@")
	if [[ ${#tools[@]} -eq 0 ]]; then
		local candidates
		candidates="$(grep -vxF -f <(printf '%s\n' "${current[@]}") <<<"${configured}" || true)"
		[[ -n "${candidates}" ]] || {
			echo "外せるツールがありません"; return 0
		}
		require_fzf
		mapfile -t tools < <(select_with_fzf "このマシンで外すツール" <<<"${candidates}")
		[[ ${#tools[@]} -gt 0 ]] || {
			echo "何も変更しません"; return 0
		}
	fi
	local tool
	for tool in "${tools[@]}"; do
		if ! grep -qxF "${tool}" <<<"${configured}"; then
			echo "設定に無いツールです: ${tool} (名前は .config/mise/*.toml のキーと同じにする)" >&2
			return 1
		fi
	done
	local new
	mapfile -t new < <(printf '%s\n' "${current[@]}" "${tools[@]}" | sed '/^$/d' | sort -u)
	write_disabled_tools "${new[@]}"
	# 外しただけではディスクと shim が残るので消す。入っていないツールは失敗するので、警告だけにして続ける
	for tool in "${tools[@]}"; do
		if ! global_mise uninstall --all "${tool}" >/dev/null 2>&1; then
			echo "${tool} はアンインストールしませんでした (インストールされていない可能性があります)" >&2
		fi
	done
	cmd_status
}

cmd_enable() {
	local install=1
	if [[ "${1:-}" == --no-install ]]; then
		install=""
		shift
	fi
	local current
	read_current
	local tools=("$@")
	if [[ ${#tools[@]} -eq 0 ]]; then
		[[ ${#current[@]} -gt 0 ]] || {
			echo "外しているツールはありません"; return 0
		}
		require_fzf
		mapfile -t tools < <(printf '%s\n' "${current[@]}" | select_with_fzf "このマシンで戻すツール")
		[[ ${#tools[@]} -gt 0 ]] || {
			echo "何も変更しません"; return 0
		}
	fi
	local tool
	for tool in "${tools[@]}"; do
		if ! printf '%s\n' "${current[@]}" | grep -qxF "${tool}"; then
			echo "外していないツールです: ${tool}" >&2
			return 1
		fi
	done
	local new
	mapfile -t new < <(printf '%s\n' "${current[@]}" | grep -vxF -f <(printf '%s\n' "${tools[@]}") || true)
	write_disabled_tools "${new[@]}"
	if [[ -n "${install}" ]]; then
		global_mise install "${tools[@]}"
	else
		echo "インストールは次の mise install (または mise bootstrap) で行われます"
	fi
	cmd_status
}

case "${1:-}" in
status) cmd_status ;;
summary) cmd_summary ;;
disable) shift && cmd_disable "$@" ;;
enable) shift && cmd_enable "$@" ;;
*)
	echo "usage: $0 status|summary|disable [tool...]|enable [--no-install] [tool...]" >&2
	exit 2
	;;
esac
