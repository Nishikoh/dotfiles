#!/usr/bin/env bash
# Worktrunk が Git の lifecycle を管理し、起動済み Herdr の表示を best effort で同期する。
set -euo pipefail

# git hook 経由で起動しても、呼び出し元の GIT_DIR 等で別の checkout を参照しない。
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

[[ $# == 3 && ( $1 == open || $1 == close ) ]] || exit 0
for tool in herdr jq flock timeout; do
	command -v "$tool" >/dev/null 2>&1 || exit 0
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

# 未起動の通常操作では Git の path 解決や lock file の作成をしない。
status=$(herdr_cmd status server --json) || exit 0
jq -e '.running == true' <<<"$status" >/dev/null || exit 0

action=$1
primary=$(fs_cmd realpath -e -- "$2") || exit 0
checkout=$(fs_cmd realpath -m -- "$3") || exit 0
[[ "$checkout" != "$primary" ]] || exit 0
common=$(git_cmd -C "$primary" rev-parse --path-format=absolute --git-common-dir) || exit 0
common=$(fs_cmd realpath -e -- "$common") || exit 0

# post-switch / post-remove は別々の background job。open と close を直列化し、
# lock 取得後に checkout を再確認して、遅れて起動した open が削除済みの表示を戻さないようにする。
fs_cmd mkdir -p "$common/wt" || exit 0
exec 9>"$common/wt/herdr-sync.lock"
# lock の保持中の herdr / git / filesystem の操作にはすべて時間制限がある。
# そのため background job の待機は制限せず、複数削除や slow server でキューが長くなっても同期イベントを落とさない。
flock 9 || { echo 'worktrunk/herdr: could not acquire sync lock' >&2; exit 0; }

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

# /proc の生存中の cwd を checkout root まで辿る。
# 同じ inode が再利用される世代番号としてではなく、同時に存在する directory object を比較する。
process_checkout_state() {
	local pid=$1 cwd=$2 actual clean cursor probe identity depth=0 trash_name suffix
	[[ "$pid" =~ ^[1-9][0-9]*$ && -n "$cwd" ]] || return 1
	probe="/proc/$pid/cwd"
	actual=$(fs_cmd readlink -- "$probe") || return 1
	[[ "$actual" == "$cwd" ]] || return 1
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
		[[ $(fs_cmd readlink -- "/proc/$pid/cwd") == "$cwd" ]] || return 1
		if [[ -n "$checkout_identity" ]]; then
			if [[ "$identity" == "$checkout_identity" ]]; then echo current; else echo stale; fi
		elif [[ "$cwd" == *' (deleted)' ]]; then
			echo stale
		else
			echo other
		fi
	elif [[ "$clean" == "$common/wt/trash/"* && "$trash_unique" == true ]]; then
		# Worktrunk の trash は <checkout basename>-<epoch>。他の worktree の trash は触らない。
		trash_name=${clean#"$common/wt/trash/"}; trash_name=${trash_name%%/*}
		suffix=${trash_name#"${checkout##*/}-"}
		[[ "$trash_name" != "$suffix" && "$suffix" =~ ^[0-9]+$ ]] || { echo other; return; }
		[[ $(fs_cmd readlink -- "/proc/$pid/cwd") == "$cwd" ]] || return 1
		echo stale
	else
		echo other
	fi
}

pane_checkout_state() {
	local id=$1 pane processes pid cwd state shell_cwd records fg_pid fg_cwd
	pane=$(herdr_cmd pane get "$id") || return 1
	cwd=$(jq -er '.result.pane.cwd | select(type == "string" and length > 0)' <<<"$pane") || return 1
	processes=$(herdr_cmd pane process-info --pane "$id") || return 1
	pid=$(jq -er '.result.process_info.shell_pid' <<<"$processes") || return 1
	jq -e '.result.process_info.foreground_processes | type == "array" and
		all(.[]; (.pid | type == "number" and . > 0 and floor == .) and
			(.cwd | type == "string" and length > 0))' <<<"$processes" >/dev/null || return 1
	# pane get の cwd は poll のキャッシュ。idle shell は process-info の同期取得を優先する。
	shell_cwd=$(jq -r --argjson pid "$pid" '.result.process_info.foreground_processes[] |
		select(.pid == $pid) | .cwd // ""' <<<"$processes") || return 1
	[[ -z "$shell_cwd" ]] || cwd=$shell_cwd
	state=$(process_checkout_state "$pid" "$cwd") || return 1
	[[ "$state" == stale ]] || { echo "$state"; return; }
	# shell が削除対象でも、別の checkout にいる foreground process があれば保護する。
	records=$(jq -er '.result.process_info.foreground_processes | select(type == "array") |
		map([.pid, .cwd] | @tsv) | join("\n")' <<<"$processes") || return 1
	while IFS=$'\t' read -r fg_pid fg_cwd; do
		[[ -n "$fg_pid" ]] || continue
		state=$(process_checkout_state "$fg_pid" "$fg_cwd") || return 1
		[[ "$state" == stale ]] || { echo other; return; }
	done <<<"$records"
	echo stale
}

close_stale_panes() {
	local listing worktrees records id panes pane_ids pane_id before
	listing=$(herdr_cmd workspace list) || return 1
	worktrees=$(herdr_cmd worktree list --cwd "$primary") || return 1
	# 同じ basename の別配置が分かる場合は trash の名前から特定できないので保護する。
	trash_unique=$(jq -n --arg path "$checkout" --arg repo "$common" \
		--argjson ws "$listing" --argjson wt "$worktrees" '
		([$ws.result.workspaces[] | select(.worktree.repo_key == $repo) | .worktree.checkout_path] +
		 [$wt.result.worktrees[].path]) | all(. == $path or (split("/")[-1] != ($path | split("/")[-1])))
	') || return 1
	records=$(jq -r --arg path "$checkout" --arg repo "$common" '
		.result.workspaces[] | select(.worktree.is_linked_worktree == true and
			.worktree.checkout_path == $path and .worktree.repo_key == $repo) | .workspace_id
	' <<<"$listing") || return 1
	while IFS= read -r id; do
		[[ -n "$id" ]] || continue
		panes=$(herdr_cmd pane list --workspace "$id") || return 1
		pane_ids=$(jq -r '.result.panes[].pane_id' <<<"$panes") || return 1
		while IFS= read -r pane_id; do
			[[ -n "$pane_id" && "$pane_id" != "${HERDR_PANE_ID:-}" ]] || continue
			refresh_checkout_identity || return 1
			before=$checkout_identity
			[[ $(pane_checkout_state "$pane_id") == stale ]] || continue
			# workspace 全体を閉じない。操作元・別 checkout・新しく追加した pane は残す。
			[[ $(pane_checkout_state "$pane_id") == stale ]] || continue
			refresh_checkout_identity || return 1
			# trash の確認中に元の root の削除が完了するのは許容する。別 root への再作成は保護する。
			[[ -z "$checkout_identity" || "$checkout_identity" == "$before" ]] || return 1
			herdr_cmd pane close "$pane_id" >/dev/null || return 1
		done <<<"$pane_ids"
	done <<<"$records"
}

ensure_checkout_pane() {
	local id=$1 panes pane_ids pane_id state before first=''
	panes=$(herdr_cmd pane list --workspace "$id") || return 1
	pane_ids=$(jq -r '.result.panes[].pane_id' <<<"$panes") || return 1
	refresh_checkout_identity || return 1
	before=$checkout_identity
	while IFS= read -r pane_id; do
		[[ -n "$pane_id" ]] || continue
		[[ -n "$first" ]] || first=$pane_id
		state=$(pane_checkout_state "$pane_id") || return 1
		[[ "$state" == current ]] && return 0
	done <<<"$pane_ids"
	[[ -n "$first" ]] || return 1
	# 判定できた別 repo の pane だけが残って dedup された場合、復帰先を用意する。
	# 確認中に削除・再作成された場合は split しない (Herdr が cwd を HOME に fallback するため)。
	checkout_exists || return 1
	refresh_checkout_identity || return 1
	[[ -n "$checkout_identity" && "$checkout_identity" == "$before" ]] || return 1
	herdr_cmd pane split "$first" --direction right --cwd "$checkout" --no-focus >/dev/null || return 1
	echo 'worktrunk/herdr: kept existing panes and added a pane for the current checkout' >&2
}

trash_unique=false
checkout_identity=''

case "$action" in
open)
	checkout_exists || exit 0
	listing=$(herdr_cmd worktree list --cwd "$primary") || exit 0
	# --cwd だけで open すると未登録の primary まで自動作成されるため、開いている親を必須にする。
	parent=$(jq -er '.result.source.source_workspace_id | select(type == "string" and length > 0)' <<<"$listing") || exit 0
	jq -e --arg path "$checkout" '
		any(.result.worktrees[]; .path == $path and .is_linked_worktree and
			(.is_bare | not) and (.is_prunable | not))
	' <<<"$listing" >/dev/null || exit 0
	# 同じ path への再作成では Herdr の path による dedup を避け、shell を新しい cwd に作る。
	close_stale_panes || exit 0
	checkout_exists || exit 0
	opened=$(herdr_cmd worktree open --workspace "$parent" --path "$checkout" --no-focus) || exit 0
	id=$(jq -er '.result.workspace.workspace_id' <<<"$opened") || exit 0
	# 新しく作った workspace は既に新 checkout の pane を持つ。初期 cwd の更新待ちで split しない。
	if jq -e '.result.already_open == true' <<<"$opened" >/dev/null; then
		ensure_checkout_pane "$id" || exit 0
	fi
	;;
close)
	# 削除された directory object に残る pane だけ閉じる。移動済みの作業は保護する。
	close_stale_panes || exit 0
	;;
esac
