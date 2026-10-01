#!/usr/bin/env bash
# Worktrunk が Git の lifecycle を管理し、起動済み Herdr の表示を best effort で同期する。
# 1 つの worktree を 1 つの workspace に対応させ、リポジトリの workspace の下に並べる。
#   open <primary> <checkout>   post-switch: workspace を用意する (focus は移動しない)
#   close <primary> <checkout>  post-remove: 削除した checkout の workspace を閉じる
#   focus <path>                herdr-shell.sh: cd の代わりに path の workspace を focus する。
#                               focus できない、または操作元の workspace なら失敗を返し、呼び出し側が cd する
set -euo pipefail

# git hook 経由で起動しても、呼び出し元の GIT_DIR 等で別の checkout を参照しない。
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

case "$#:${1:-}" in
3:open | 3:close | 2:focus) ;;
*) exit 0 ;;
esac
action=$1
# Herdr は pane を閉じるとき、その pane の session のプロセスをすべて終了させる (nohup や SIGHUP の無視も効かない)。
# 操作元の pane から起動した close が、自分が閉じる pane と一緒に終了しないよう別 session に移る。
if [[ "$action" == close && -z "${WORKTRUNK_HERDR_DETACHED:-}" ]] && command -v setsid >/dev/null 2>&1; then
	WORKTRUNK_HERDR_DETACHED=1 exec setsid -w bash "${BASH_SOURCE[0]}" "$@"
fi
# 同期できない場合、hook は成功扱いで終わり、focus は呼び出し側の cd に任せる。
skip() {
	[[ "$action" != focus ]] || exit 1
	exit 0
}
for tool in herdr jq flock timeout; do
	command -v "$tool" >/dev/null 2>&1 || skip
done

herdr_cmd() {
	# API コマンドはサーバーを開始しない。子孫が残っても repo の lock を保持させない。
	# while read の入力を読み取らないよう stdin も渡さない。
	timeout -k 1s 3s herdr "$@" </dev/null 9>&- 2>/dev/null
}

git_cmd() {
	# lock の保持中に応答しない filesystem で止まり続けないよう、git にも時間制限を設ける。
	timeout -k 1s 5s git "$@" </dev/null 9>&- 2>/dev/null
}

fs_cmd() {
	# filesystem 操作とその子孫にも lock を渡さず、TERM で終わらない場合は KILL する。
	timeout -k 1s 5s "$@" </dev/null 9>&- 2>/dev/null
}

# 自分と祖先 (Worktrunk の hook runner) の pid。session の確認から除く。
ancestors=' '
proc_pid=$$
while [[ "$proc_pid" =~ ^[1-9][0-9]*$ && "$proc_pid" != 1 ]]; do
	ancestors+="$proc_pid "
	{ read -r proc_stat <"/proc/$proc_pid/stat"; } 2>/dev/null || break
	read -r _ proc_pid _ <<<"${proc_stat##*) }"
done

# pane の shell の session に、shell 以外のプロセス (background job、Worktrunk の削除や hook) があるか。
# pane を閉じると Herdr がこれらも終了させるので、ある場合は閉じない。確認できない場合もあるとみなす。
session_has_others() {
	local shell=$1 sid stat line pid session
	{ read -r line <"/proc/$shell/stat"; } 2>/dev/null || return 0
	read -r _ _ _ sid _ <<<"${line##*) }"
	[[ "$sid" =~ ^[0-9]+$ ]] || return 0
	for stat in /proc/[0-9]*/stat; do
		{ read -r line <"$stat"; } 2>/dev/null || continue
		pid=${stat#/proc/}; pid=${pid%/stat}
		read -r _ _ _ session _ <<<"${line##*) }"
		[[ "$session" == "$sid" && "$pid" != "$shell" && "$ancestors" != *" $pid "* ]] && return 0
	done
	return 1
}

# 未起動の通常操作では Git の path 解決や lock file の作成をしない。
status=$(herdr_cmd status server --json) || skip
jq -e '.running == true' <<<"$status" >/dev/null || skip

if [[ "$action" == focus ]]; then
	checkout=$(fs_cmd realpath -e -- "$2") || exit 1
	# 移動先から primary を求める。bare repo の worktree は Herdr の API が扱えないので cd に任せる。
	worktree_list=$(git_cmd -C "$checkout" worktree list --porcelain) || exit 1
	[[ "$worktree_list" == 'worktree '* ]] || exit 1
	primary=${worktree_list%%$'\n'*}
	primary=${primary#worktree }
	[[ "$worktree_list" != *$'\nbare\n'* && "$worktree_list" != *$'\nbare' ]] || exit 1
	primary=$(fs_cmd realpath -e -- "$primary") || exit 1
else
	primary=$(fs_cmd realpath -e -- "$2") || exit 0
	checkout=$(fs_cmd realpath -m -- "$3") || exit 0
	[[ "$checkout" != "$primary" ]] || exit 0
fi
common=$(git_cmd -C "$primary" rev-parse --path-format=absolute --git-common-dir) || skip
common=$(fs_cmd realpath -e -- "$common") || skip

# post-switch / post-remove は別々の background job。open と close を直列化し、
# lock 取得後に checkout を再確認して、遅れて起動した open が削除済みの表示を戻さないようにする。
# post-remove は wt の終了前に始まる。操作元の pane の wt と focus、Worktrunk の background 削除と
# 他の hook が終わってから lock を取る。lock の保持中に待つと focus が lock を待って cd に戻ってしまう。
# エージェント等が foreground にいる場合、その pane は閉じないので待たない。60 秒で諦め、pane を残す。
if [[ "$action" == close && -n "${HERDR_PANE_ID:-}" ]]; then
	# herdr の応答停止で待ちが延びないよう、回数ではなく経過時間で打ち切る。
	deadline=$((SECONDS + 60))
	while ((SECONDS < deadline)); do
		processes=$(herdr_cmd pane process-info --pane "$HERDR_PANE_ID") || break
		shell_pid=$(jq -er '.result.process_info.shell_pid | select(type == "number")' <<<"$processes") || break
		if jq -e --argjson pid "$shell_pid" '.result.process_info.foreground_processes |
			length == 1 and .[0].pid == $pid' <<<"$processes" >/dev/null; then
			session_has_others "$shell_pid" || break
		elif ! jq -e '.result.process_info.foreground_processes | any(.[]; .name == "wt" or
			((.cmdline // "") | contains("herdr-hook.sh focus")))' <<<"$processes" >/dev/null; then
			break
		fi
		sleep 0.2
	done
fi

fs_cmd mkdir -p "$common/wt" || skip
exec 9>"$common/wt/herdr-sync.lock"
if [[ "$action" == focus ]]; then
	# 対話中の shell を待たせ続けない。取得できなければ cd に任せる。
	flock -w 5 9 || exit 1
else
	# lock の保持中の herdr / git / filesystem の操作にはすべて時間制限がある。
	# そのため background job の待機は制限せず、複数削除や slow server でキューが長くなっても同期イベントを落とさない。
	flock 9 || { echo 'worktrunk/herdr: could not acquire sync lock' >&2; exit 0; }
fi

# missing と読み取り失敗を区別し、確認できない checkout では同期を中止する。
checkout_exists() {
	local paths root git_common code
	fs_cmd test -d "$checkout" || { code=$?; [[ $code == 1 ]] && return 1; return 2; }
	paths=$(git_cmd -C "$checkout" rev-parse --path-format=absolute --show-toplevel --git-common-dir) || return 2
	{ IFS= read -r root && IFS= read -r git_common; } <<<"$paths" || return 2
	root=$(fs_cmd realpath -e -- "$root") || return 2
	git_common=$(fs_cmd realpath -e -- "$git_common") || return 2
	[[ "$root" == "$checkout" && "$git_common" == "$common" ]] || return 2
}

refresh_checkout_identity() {
	local code
	checkout_identity=$(fs_cmd stat -Lc '%d:%i' -- "$checkout") && return 0
	# stat が失敗しただけでは削除済みとしない。
	fs_cmd test -e "$checkout" && return 1
	code=$?
	[[ $code == 1 ]] || return 1
	# test の 1 は権限不足でも返る。親へアクセスできない場合は保護する。
	fs_cmd realpath -e -- "${checkout%/*}" >/dev/null || return 1
	fs_cmd test -x "${checkout%/*}" || return 1
	checkout_identity=''
}

# pane の shell の pid / cwd と、shell だけが動いている (foreground も background job も無い) かを読む。
read_pane() {
	local id=$1 processes pane
	processes=$(herdr_cmd pane process-info --pane "$id") || return 1
	pane_pid=$(jq -er '.result.process_info.shell_pid | select(type == "number" and . > 0 and floor == .)' <<<"$processes") || return 1
	if jq -e --argjson pid "$pane_pid" '.result.process_info.foreground_processes |
		type == "array" and length == 1 and .[0].pid == $pid' <<<"$processes" >/dev/null &&
		! session_has_others "$pane_pid"; then
		pane_idle=true
	else
		pane_idle=false
	fi
	# pane get の cwd は poll のキャッシュ。idle shell は process-info の同期取得を優先する。
	pane_cwd=$(jq -r --argjson pid "$pane_pid" '.result.process_info.foreground_processes |
		if type == "array" then .[] | select(.pid == $pid) | .cwd // "" else "" end' <<<"$processes") || return 1
	[[ -z "$pane_cwd" ]] || return 0
	pane=$(herdr_cmd pane get "$id") || return 1
	pane_cwd=$(jq -er '.result.pane.cwd | select(type == "string" and length > 0)' <<<"$pane") || return 1
}

# shell の cwd が current (現在の checkout) / dead (削除済み) / other のどれかを返す。
# /proc の生存中の cwd を checkout root まで辿り、同時に存在する directory object を比較する。
pane_location() {
	local cwd=$pane_cwd clean probe cursor identity depth=0
	[[ -n "$cwd" ]] || return 1
	probe="/proc/$pane_pid/cwd"
	[[ $(fs_cmd readlink -- "$probe") == "$cwd" ]] || return 1
	clean=${cwd%" (deleted)"}
	if [[ "$clean" == "$checkout" || "$clean" == "$checkout/"* ]]; then
		cursor=$clean
		while [[ "$cursor" != "$checkout" ]]; do
			(( depth += 1 )); [[ $depth -le 64 ]] || return 1
			cursor=${cursor%/*}
			probe+='/..'
		done
		identity=$(fs_cmd stat -Lc '%d:%i' -- "$probe") || return 1
		# stat 中に cd した場合は判定を使わない。
		[[ $(fs_cmd readlink -- "/proc/$pane_pid/cwd") == "$cwd" ]] || return 1
		if [[ -n "$checkout_identity" ]]; then
			if [[ "$identity" == "$checkout_identity" ]]; then echo current; else echo dead; fi
		elif [[ "$cwd" == *' (deleted)' ]]; then
			echo dead
		else
			echo other
		fi
	elif [[ "$cwd" == *' (deleted)' || "$clean" == "$common/wt/trash/"* ]]; then
		# wt remove は checkout を trash に移してから消す。trash の中は削除途中の checkout だけ。
		echo dead
	else
		echo other
	fi
}

# 閉じる条件: removed は待機中のすべての pane、dead は削除済みの場所にいる待機中の pane。
# 何かを実行中の pane (エージェント、エディタ、dev server など) はどちらでも残す。
pane_closable() {
	local id=$1 rule=$2 location
	read_pane "$id" || return 1
	[[ "$pane_idle" == true ]] || return 1
	case "$rule" in
	removed) ;;
	dead)
		location=$(pane_location) || return 1
		[[ "$location" == dead ]]
		;;
	*) return 1 ;;
	esac
}

close_pane_if() {
	local id=$1 rule=$2 before
	refresh_checkout_identity || return 1
	before=$checkout_identity
	pane_closable "$id" "$rule" || return 0
	# 判定中の削除完了は許容する。別 root への再作成は保護する。
	refresh_checkout_identity || return 1
	[[ -z "$checkout_identity" || "$checkout_identity" == "$before" ]] || return 1
	herdr_cmd pane close "$id" >/dev/null || return 1
}

workspace_pane_ids() {
	herdr_cmd pane list --workspace "$1" | jq -r '.result.panes[].pane_id'
}

# 対象 checkout の workspace と、worktree が無くなった同じ repo の workspace (孤立) を片付ける。
# 孤立は --no-hooks / git worktree での削除や、`wt step relocate` の後に switch せず削除した場合に残る。
# mode=close: 対象 checkout の削除後。登録が無くなった対象の workspace の待機中の pane を閉じ、最後の pane で workspace も閉じる。
#             同じパスに再登録されていれば (遅れて届いた post-remove)、削除済みの場所の pane だけを閉じる。
# mode=open: 同じパスの再作成や --no-hooks の削除で残った、削除済みの場所の pane だけを閉じる。
prune_workspaces() {
	local mode=$1 worktrees=${2:-} listing records id kind rule pane_ids pane_id
	listing=$(herdr_cmd workspace list) || return 1
	focused=$(jq -r '.result.workspaces[] | select(.focused) | .workspace_id' <<<"$listing") || return 1
	pruned=()
	[[ -n "$worktrees" ]] || worktrees=$(herdr_cmd worktree list --cwd "$primary") || return 1
	records=$(jq -r --arg path "$checkout" --arg repo "$common" --argjson wt "$worktrees" '
		[$wt.result.worktrees[] | select(.is_prunable | not) | .path] as $live |
		.result.workspaces[] | select(.worktree.is_linked_worktree == true and .worktree.repo_key == $repo) |
		if .worktree.checkout_path == $path then
			"\(.workspace_id)\t\(if $live | index($path) then "target" else "removed" end)"
		elif (.worktree.checkout_path as $p | $live | index($p)) == null then "\(.workspace_id)\torphan"
		else empty end
	' <<<"$listing") || return 1
	refresh_checkout_identity || return 1
	while IFS=$'\t' read -r id kind; do
		[[ -n "$id" ]] || continue
		rule=dead
		# merge などの background 削除では、登録の解除後もディレクトリが残っている間に post-remove が始まる。
		# そのため削除済みかどうかは、ディレクトリではなく Git の登録で判定する。
		[[ "$mode" == close && "$kind" == removed ]] && rule=removed
		pruned+=("$id")
		pane_ids=$(workspace_pane_ids "$id") || return 1
		while IFS= read -r pane_id; do
			[[ -n "$pane_id" ]] || continue
			close_pane_if "$pane_id" "$rule" || return 1
		done <<<"$pane_ids"
	done <<<"$records"
}

# repo の workspace を返す。無ければ focus せずに作る。引数は取得済みの worktree list。
ensure_parent() {
	local listing=${1:-} created
	[[ -n "$listing" ]] || listing=$(herdr_cmd worktree list --cwd "$primary") || return 1
	jq -er '.result.source.source_workspace_id | select(type == "string" and length > 0)' <<<"$listing" && return 0
	created=$(herdr_cmd workspace create --cwd "$primary" --no-focus) || return 1
	jq -er '.result.workspace.workspace_id' <<<"$created"
}

ensure_checkout_pane() {
	local id=$1 panes pane_ids pane_id target before location
	panes=$(herdr_cmd pane list --workspace "$id") || return 1
	pane_ids=$(jq -r '.result.panes[].pane_id' <<<"$panes") || return 1
	refresh_checkout_identity || return 1
	before=$checkout_identity
	while IFS= read -r pane_id; do
		[[ -n "$pane_id" ]] || continue
		# 操作元の pane があれば、これから cd する可能性があるので追加しない。
		[[ "$pane_id" != "${HERDR_PANE_ID:-}" ]] || return 0
		# 状態を確認できない pane、何かを実行中の pane は、現在の checkout で作業中かもしれないので追加しない。
		read_pane "$pane_id" && [[ "$pane_idle" == true ]] || return 0
		location=$(pane_location) || return 0
		[[ "$location" != current ]] || return 0
	done <<<"$pane_ids"
	# 判定できた別の場所の pane だけが残って dedup された場合、復帰先を用意する。
	# 確認中に削除・再作成された場合は split しない (Herdr が cwd を HOME に fallback するため)。
	checkout_exists || return 1
	refresh_checkout_identity || return 1
	[[ -n "$checkout_identity" && "$checkout_identity" == "$before" ]] || return 1
	# 表示中の tab の pane を分割する。focus の情報が無ければ先頭の pane を使う。
	target=$(jq -er 'first(.result.panes[] | select(.focused)) // .result.panes[0] | .pane_id' <<<"$panes") || return 1
	herdr_cmd pane split "$target" --direction right --cwd "$checkout" --no-focus >/dev/null || return 1
	echo 'worktrunk/herdr: kept existing panes and added a pane for the current checkout' >&2
}

# checkout の workspace を用意し、その ID を返す。
open_workspace() {
	local worktrees parent opened id
	checkout_exists || return 1
	worktrees=$(herdr_cmd worktree list --cwd "$primary") || return 1
	jq -e --arg path "$checkout" '
		any(.result.worktrees[]; .path == $path and .is_linked_worktree and
			(.is_bare | not) and (.is_prunable | not))
	' <<<"$worktrees" >/dev/null || return 1
	parent=$(ensure_parent "$worktrees") || return 1
	# 同じパスへの再作成では Herdr の path による dedup を避け、shell を新しい cwd に作る。
	prune_workspaces open "$worktrees" || return 1
	checkout_exists || return 1
	opened=$(herdr_cmd worktree open --workspace "$parent" --path "$checkout" --no-focus) || return 1
	id=$(jq -er '.result.workspace.workspace_id' <<<"$opened") || return 1
	# 新しく作った workspace は既に新 checkout の pane を持つ。初期 cwd の更新待ちで split しない。
	# `wt step relocate` (hook を実行しない) で移動した checkout も、Herdr が pane の場所から既存の workspace を再利用する。
	if jq -e '.result.already_open == true' <<<"$opened" >/dev/null; then
		ensure_checkout_pane "$id" || true
	fi
	echo "$id"
}

checkout_identity=''
pane_pid='' pane_cwd='' pane_idle=false
focused=''
pruned=()

case "$action" in
open)
	open_workspace >/dev/null || exit 0
	;;
close)
	# 削除した checkout の workspace を閉じる。何かを実行中の pane は残す。
	prune_workspaces close || exit 0
	# 見ていた workspace が閉じたら repo の workspace に戻す。
	if [[ -n "$focused" && " ${pruned[*]} " == *" $focused "* ]] && ! herdr_cmd workspace get "$focused" >/dev/null; then
		parent=$(herdr_cmd worktree list --cwd "$primary" |
			jq -er '.result.source.source_workspace_id | select(type == "string" and length > 0)') &&
			herdr_cmd workspace focus "$parent" >/dev/null || true
	fi
	;;
focus)
	if [[ "$checkout" == "$primary" ]]; then
		id=$(ensure_parent) || exit 1
	else
		id=$(open_workspace) || exit 1
	fi
	# 操作元と同じ workspace 内の移動は、通常どおり cd する。
	if [[ -n "${HERDR_PANE_ID:-}" ]]; then
		current=$(herdr_cmd pane get "$HERDR_PANE_ID" | jq -r '.result.pane.workspace_id') || current=''
		[[ "$current" != "$id" ]] || exit 1
	fi
	herdr_cmd workspace focus "$id" >/dev/null || exit 1
	;;
esac
