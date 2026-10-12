#!/usr/bin/env bash
# このマシンで外すツール (mise の disable_tools) を表示・変更する。mise.toml の tools:* タスクと final hook から呼ぶ。
#
#   tools.sh status                          外しているツールと、その設定元を表示する
#   tools.sh summary                         外しているツールを 1 行で表示する (bootstrap の最後に表示する)
#   tools.sh disable [tool...]               外してアンインストールする。省略すると fzf で選ぶ
#   tools.sh enable [--no-install] [tool...] 戻してインストールする。省略すると fzf で選ぶ
#   tools.sh preset [name|off]               許可リストのプリセット (.config/mise/presets/) に切り替える。off で戻す。省略すると一覧を表示する
#
# 既定では .config/mise/config.toml の disable_tools (プリセット) を外す。マシンごとの値は
# ~/.config/mise/config.local.toml (git に無視される) に書く。mise ではこの値がプリセットに足されず置き換わるので、
# 今の値にツールを足したり引いたりした全体を書く。
# enable_tools (許可リスト) を設定したマシン (最小構成のマシン) では、status と summary で一覧を表示し、disable と enable は失敗する。
# 一覧は `tools.sh preset` で切り替える (プリセットは .config/mise/presets/。README の「最小構成のマシン」)。
# preset は選んだ名前を enable_tools の行に印 (# preset: <name>) として残し、プリセットが更新されたら summary と status で知らせる。
# `mise config set` は空のリストを書けない (--remove で空にするとキーごと消えてプリセットに戻る) ので、行を直接書き換える。
set -euo pipefail

config_dir="${HOME}/.config/mise"
# 外さないツール (README の「マシンごとにツールを外す」)。npm: と pipx: のツール、git の hook、zsh の設定と tools タスクの選択で使う
protected_tools="bun
uv
lefthook
fzf"
preset_file="${config_dir}/config.toml"
local_file="${config_dir}/config.local.toml"
presets_dir="${config_dir}/presets"

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

# ~/.config/mise/config.local.toml の [settings] の key を line に置き換える (line が空なら key を消す)。ほかの内容は残す。
# 既存の書き方 (settings.key = ... や複数行の配列) も捨て、書くときは [settings] の直後に書く。
# 書く前に mise で読み、expected (ソートした値。空なら key が無いこと) と違えば何も変えずに失敗する。
# [settings] しか残らなければ (タスクが作ったファイル) ファイルごと消し、残すときは中身だけを書き換える (symlink やパーミッションを変えない)
write_local_setting() {
	local key="$1" line="$2" expected="$3"
	if [[ -z "${line}" && ! -f "${local_file}" ]]; then
		return 0
	fi
	# 一時ファイルはリポジトリの外に作る (~/.config/mise はリポジトリへの symlink なので、隣に作ると中断したときに残る)
	local tmp
	tmp="$(mktemp --suffix=.toml)"
	if [[ -f "${local_file}" ]]; then
		cat "${local_file}" >"${tmp}"
	fi
	local edited
	edited="$(awk -v key="${key}" -v line="${line}" '
		# 既存の key (settings.key や複数行の配列を含む) は捨てて、書くときは [settings] の直後に書く
		skip { if (/\]/) skip = 0; next }
		$0 ~ ("^[[:space:]]*(settings\\.)?" key "[[:space:]]*=") { if ($0 !~ /\]/) skip = 1; next }
		{ print }
		line != "" && /^[[:space:]]*\[settings\][[:space:]]*(#.*)?$/ && !done { print line; done = 1 }
		END {
			if (line != "" && !done) {
				if (NR > 0) print ""
				print "[settings]"
				print line
			}
		}
	' "${tmp}")"
	if [[ -z "${line}" ]]; then
		# 消したあとに残った空の [settings] (と前後の空行) は取り除く
		edited="$(printf '%s\n' "${edited}" | awk '
			{ lines[NR] = $0 }
			END {
				n = NR
				while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
				if (n > 0 && lines[n] ~ /^[[:space:]]*\[settings\][[:space:]]*(#.*)?$/) n--
				while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
				for (i = 1; i <= n; i++) print lines[i]
			}
		')"
	fi
	printf '%s\n' "${edited}" >"${tmp}"
	# 上で扱えない書き方 (settings = { ... } など) だと、キーが重複してグローバルの設定が読めなくなる。
	# 書き込む前に mise で読み、意図した値になっていなければ何も変えずに止める
	local ok=""
	if global_mise config get -f "${tmp}" >/dev/null 2>&1; then
		if [[ -n "${line}" ]]; then
			[[ "$(global_mise config get -f "${tmp}" "settings.${key}" | to_lines | LC_ALL=C sort -u)" == "${expected}" ]] && ok=1
		else
			global_mise config get -f "${tmp}" "settings.${key}" >/dev/null 2>&1 || ok=1
		fi
	fi
	if [[ -z "${ok}" ]]; then
		rm -f "${tmp}"
		echo "${local_file} の ${key} を書き換えられませんでした。手で直してください (README の「マシンごとにツールを外す」)" >&2
		return 1
	fi
	if grep -qvE '^[[:space:]]*(\[settings\][[:space:]]*(#.*)?)?$' "${tmp}"; then
		cat "${tmp}" >"${local_file}"
	else
		rm -f "${local_file}"
	fi
	rm -f "${tmp}"
}

# ~/.config/mise/config.local.toml の disable_tools を引数のツールで置き換える。プリセットと同じになるときは消して、プリセットに従わせる
# (プリセットのコピーを持つと、あとでプリセットを変えてもこのマシンに反映されないため)
write_disabled_tools() {
	local expected
	expected="$(printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort -u)"
	local line=""
	if [[ "${expected}" != "$(preset_tools)" ]]; then
		local value=""
		local tool
		for tool in "$@"; do
			value+="${value:+, }\"${tool}\""
		done
		line="disable_tools = [${value}]"
	elif ! has_local_setting; then
		return 0
	fi
	write_local_setting disable_tools "${line}" "${expected}" || return 1
	if [[ -z "${line}" ]]; then
		echo "プリセットと同じになったので、このマシンの設定を消しました (以後はプリセットに従います)"
	fi
}

# 標準入力の候補から fzf で複数選び、選んだものを出力する。何も選ばずに ENTER、または ESC で抜けたときは何も出力しない。
# fzf --multi は何も選ばずに ENTER を押すとカーソル行を返すので、選んだ数 ($FZF_SELECT_COUNT) が 0 なら abort にする
select_with_fzf() {
	# shellcheck disable=SC2016 # $FZF_SELECT_COUNT は fzf が実行するシェルで展開する
	fzf --multi \
		--header="$1 (TAB で選択、ENTER で決定、ESC で中止)" \
		--bind 'enter:transform([ "$FZF_SELECT_COUNT" -eq 0 ] && echo abort || echo accept)' || true
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

# 許可リスト (enable_tools) が設定されているか。環境変数 MISE_ENABLE_TOOLS も数える (最初の bootstrap を環境変数で絞るため)。
# リポジトリの別のチェックアウトの設定は見ない
allowlist_mode() {
	(cd / && env -u MISE_DISABLE_TOOLS mise settings get enable_tools) >/dev/null 2>&1
}

# 効いている許可リストを名前順に 1 行ずつ出す (環境変数 MISE_ENABLE_TOOLS を含む)
allowed_lines() {
	(cd / && env -u MISE_DISABLE_TOOLS mise settings get enable_tools) | to_lines | LC_ALL=C sort -u
}

allowed_tools() {
	allowed_lines | join_list
}

# プリセットのファイルの一覧を名前順に 1 行ずつ出す
preset_list() {
	global_mise config get -f "$1" settings.enable_tools | to_lines | LC_ALL=C sort -u
}

# 一覧 (名前順に 1 行ずつ) と同じプリセットの名前を出す。無ければ何も出さない
matching_preset() {
	local name
	while IFS= read -r name; do
		if [[ -n "${name}" && "$(preset_list "${presets_dir}/${name}.toml" 2>/dev/null)" == "$1" ]]; then
			echo "${name}"
			return 0
		fi
	done < <(preset_names)
	return 0
}

# tools:preset が enable_tools の行に残した印 (# preset: <name>) から、このマシンで選んだプリセットの名前を出す
chosen_preset() {
	if [[ -f "${local_file}" ]]; then
		sed -nE 's/^[[:space:]]*(settings\.)?enable_tools[[:space:]]*=.*#[[:space:]]*preset:[[:space:]]*([A-Za-z0-9_-]+).*$/\2/p' "${local_file}" | head -n 1
	fi
}

# 許可リストで気づきにくい状態を知らせる (bootstrap の最後の summary と tools:status で表示する)
allowlist_notes() {
	local name
	# 環境変数 MISE_ENABLE_TOOLS だけで、このマシンには保存されていない (最初の bootstrap の直後)
	if ! global_mise settings get enable_tools >/dev/null 2>&1; then
		name="$(matching_preset "$(allowed_lines)")"
		echo "注意: 許可リストがこのマシンに保存されていません (MISE_ENABLE_TOOLS はその実行だけに効く)。このままだと次の mise upgrade や bootstrap で、許可リストに無いツールも入ります"
		echo "  保存する: mise run tools:preset ${name:-<name>}"
		return 0
	fi
	# config.local.toml には選んだ時点の一覧がコピーされるので、あとでプリセットを更新しても反映されない
	name="$(chosen_preset)"
	[[ -n "${name}" ]] || return 0
	if [[ ! -f "${presets_dir}/${name}.toml" ]]; then
		echo "注意: 選んだプリセット ${name} がありません。mise run tools:preset で選び直してください"
	elif [[ "$(global_mise config get -f "${local_file}" settings.enable_tools | to_lines | LC_ALL=C sort -u)" != "$(preset_list "${presets_dir}/${name}.toml")" ]]; then
		echo "注意: 一覧がプリセット ${name} と違います (${name} が更新されたか、手で変えた)。${name} に合わせる: mise run tools:preset ${name}"
	fi
}

cmd_status() {
	local disabled here allowed name
	if allowlist_mode; then
		allowed="$(allowed_tools)"
		echo "許可リスト: ${allowed:-なし} (enable_tools。ここに無いツールは入らず、disable_tools は使われない)"
		name="$(chosen_preset)"
		if [[ -n "${name}" ]]; then
			echo "  プリセット: ${name}"
		fi
		allowlist_notes
		echo "変更: mise run tools:preset <name> (プリセットに切り替える) / mise run tools:preset off (戻す)"
		return 0
	fi
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
	local disabled allowed
	if allowlist_mode; then
		allowed="$(allowed_tools)"
		echo "許可リスト: ${allowed:-なし} (enable_tools。ここに無いツールは入らない)"
		allowlist_notes || true
		return 0
	fi
	disabled="$(disabled_tools 2>/dev/null | join_list)" || return 0
	if [[ -n "${disabled}" ]]; then
		echo "外しているツール: ${disabled} (戻すときは mise run tools:enable)"
	fi
}

cmd_disable() {
	local current configured
	if allowlist_mode; then
		echo "このマシンは許可リスト (enable_tools) でツールを決めています。mise run tools:preset off で戻すか、${local_file} を手で編集してください" >&2
		return 1
	fi
	read_current
	configured="$(configured_tools)"
	local tools=("$@")
	if [[ ${#tools[@]} -eq 0 ]]; then
		local candidates
		candidates="$(grep -vxF -f <(printf '%s\n' "${current[@]}" "${protected_tools}") <<<"${configured}" || true)"
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
		if grep -qxF "${tool}" <<<"${protected_tools}"; then
			echo "外さないツールです: ${tool} (ほかの設定やツールが使う。README の「マシンごとにツールを外す」)" >&2
			return 1
		fi
	done
	local new
	mapfile -t new < <(printf '%s\n' "${current[@]}" "${tools[@]}" | sed '/^$/d' | sort -u)
	write_disabled_tools "${new[@]}"
	# 外しただけではディスクと shim が残るので消す (入っていないツールでは何もせずに成功する)。
	# mise のデータディレクトリが無ければ、何も入っていないので消すものも無い (mise uninstall はそこで失敗する)
	local failed="" err
	local data_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/mise}"
	[[ -d "${data_dir}" ]] || tools=()
	for tool in "${tools[@]}"; do
		if ! err="$(global_mise uninstall --all "${tool}" 2>&1 >/dev/null)"; then
			echo "${tool} をアンインストールできませんでした:" >&2
			printf '%s\n' "${err}" >&2
			failed=1
		fi
	done
	cmd_status
	[[ -z "${failed}" ]]
}

cmd_enable() {
	local install=1
	if allowlist_mode; then
		echo "このマシンは許可リスト (enable_tools) でツールを決めています。mise run tools:preset off で戻すか、${local_file} を手で編集してください" >&2
		return 1
	fi
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

# 使えるプリセット (.config/mise/presets/*.toml の名前) を 1 行ずつ出す
preset_names() {
	local f
	for f in "${presets_dir}"/*.toml; do
		[[ -f "${f}" ]] && basename "${f}" .toml
	done
	return 0
}

# 許可リスト (enable_tools) をプリセットに切り替える。off なら許可リストをやめて、外すツールの設定 (disable_tools) に戻す
cmd_preset() {
	local name="${1:-}"
	local names
	names="$(preset_names | paste -sd, - | sed 's/,/, /g')"
	if [[ -z "${name}" ]]; then
		echo "プリセット: ${names:-なし}"
		echo "使い方: mise run tools:preset <name> (許可リストにする) / mise run tools:preset off (戻す)"
		return 0
	fi
	if [[ "${name}" == off ]]; then
		write_local_setting enable_tools "" ""
		cmd_status
		return 0
	fi
	local file="${presets_dir}/${name}.toml"
	if [[ ! "${name}" =~ ^[A-Za-z0-9_-]+$ || ! -f "${file}" ]]; then
		echo "プリセットがありません: ${name} (プリセット: ${names:-なし})" >&2
		return 1
	fi
	local tools
	if ! tools="$(preset_list "${file}")" || [[ -z "${tools}" ]]; then
		echo "${file} に enable_tools (ツールの一覧) がありません" >&2
		return 1
	fi
	# 一覧の名前は設定にあるものだけ (mise は知らない名前を何も言わずに無視するため)
	local configured tool value=""
	configured="$(configured_tools)"
	while IFS= read -r tool; do
		if ! grep -qxF "${tool}" <<<"${configured}"; then
			echo "設定に無いツールです: ${tool} (プリセット ${name}。名前は .config/mise/*.toml のキーと同じにする)" >&2
			return 1
		fi
		value+="${value:+, }\"${tool}\""
	done <<<"${tools}"
	# 選んだ名前を印として残す (プリセットが更新されたことに allowlist_notes で気づけるように)
	write_local_setting enable_tools "enable_tools = [${value}] # preset: ${name}" "${tools}"
	cmd_status
}

case "${1:-}" in
status) cmd_status ;;
summary) cmd_summary ;;
disable) shift && cmd_disable "$@" ;;
enable) shift && cmd_enable "$@" ;;
preset) shift && cmd_preset "$@" ;;
*)
	echo "usage: $0 status|summary|disable [tool...]|enable [--no-install] [tool...]|preset [name|off]" >&2
	exit 2
	;;
esac
