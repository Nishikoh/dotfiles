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

# checkout が $common の linked worktree として存在すれば、その管理ディレクトリを git_dir に設定する。
checkout_exists() {
	local paths root git_common
	fs_cmd test -d "$checkout" || return 1
	paths=$(git_cmd -C "$checkout" rev-parse --path-format=absolute \
		--show-toplevel --git-common-dir --absolute-git-dir) || return 1
	{ IFS= read -r root && IFS= read -r git_common && IFS= read -r git_dir; } <<<"$paths" || return 1
	[[ $(fs_cmd realpath -e -- "$root") == "$checkout" &&
		$(fs_cmd realpath -e -- "$git_common") == "$common" ]]
}

close_workspaces() {
	local stale_only=$1 listing records id known panes
	listing=$(herdr_cmd workspace list) || return 1
	records=$(jq -r --arg path "$checkout" --arg repo "$common" '
		.result.workspaces[] | select(.worktree.is_linked_worktree == true and
			.worktree.checkout_path == $path and .worktree.repo_key == $repo) |
		[.workspace_id, (.tokens.dotfiles_wt_checkout // "")] | @tsv
	' <<<"$listing") || return 1
	while IFS=$'\t' read -r id known; do
		[[ -n "$id" ]] || continue
		if [[ "$stale_only" == true ]]; then
			if [[ -n "$known" && -n "$generation" ]]; then
				[[ "$known" != "$generation" ]] || continue
			else
				panes=$(herdr_cmd pane list --workspace "$id") || return 1
				# 手動登録など識別情報がない場合は pane の cwd から削除済みの checkout を判定する。
				# wt remove は checkout を $common/wt/trash に移してから削除し、git worktree remove はその場で削除する。
				# 子ディレクトリの削除は同じ checkout 内の make clean などと区別できないので、
				# shell を終了させないよう trash の中か、Linux が削除済みと示す checkout の root だけを対象にする。
				jq -e --arg path "$checkout" --arg trash "$common/wt/trash/" '
					any(.result.panes[]; [.cwd, .foreground_cwd][] | select(type == "string") |
						startswith($trash) or . == ($path + " (deleted)"))
				' <<<"$panes" >/dev/null || continue
			fi
		fi
		herdr_cmd workspace close "$id" >/dev/null || return 1
	done <<<"$records"
}

# path が同じでも、linked worktree の管理ディレクトリ (.git/worktrees/<name>) が違えば別の checkout。
# Git は削除時に管理ディレクトリを消し、再作成時に新しく作るので、そこに置いた ID で世代を区別する。
# inode / birth time と違い、filesystem の種類や remount の影響を受けない。
# ID を用意できない場合は識別情報なしとして扱う。
exists=false
git_dir=''
generation=''
if checkout_exists; then
	exists=true
	id_file="$git_dir/dotfiles-herdr-checkout"
	# shell の redirect は timeout の外で開かれるので、書き込みも timeout の中で行う。
	if ! fs_cmd test -s "$id_file" && new_id=$(</proc/sys/kernel/random/uuid); then
		fs_cmd sh -c 'printf %s "$1" >"$2.tmp" && mv -f -- "$2.tmp" "$2"' _ "$new_id" "$id_file" || true
	fi
	generation=$(fs_cmd cat -- "$id_file") || generation=''
fi

case "$action" in
open)
	[[ "$exists" == true ]] || exit 0
	listing=$(herdr_cmd worktree list --cwd "$primary") || exit 0
	# --cwd だけで open すると未登録の primary まで自動作成されるため、開いている親を必須にする。
	parent=$(jq -er '.result.source.source_workspace_id | select(type == "string" and length > 0)' <<<"$listing") || exit 0
	jq -e --arg path "$checkout" '
		any(.result.worktrees[]; .path == $path and .is_linked_worktree and
			(.is_bare | not) and (.is_prunable | not))
	' <<<"$listing" >/dev/null || exit 0
	# 同じ path への再作成では Herdr の path による dedup を避け、shell を新しい cwd に作る。
	close_workspaces true || exit 0
	opened=$(herdr_cmd worktree open --workspace "$parent" --path "$checkout" --no-focus) || exit 0
	id=$(jq -er '.result.workspace.workspace_id' <<<"$opened") || exit 0
	# Herdr が path の dedup で既存の workspace を返した場合は識別情報を付けない。
	# 識別情報のない古い workspace (子ディレクトリに残った shell など) を新しい checkout のものとして扱わないため。
	# 初回の report-metadata が失敗した workspace も、以後は識別情報なしとして pane の cwd で判定する。
	jq -e '.result.already_open == false' <<<"$opened" >/dev/null || exit 0
	[[ -n "$generation" ]] || exit 0
	herdr_cmd workspace report-metadata "$id" --source dotfiles-worktrunk \
		--token "dotfiles_wt_checkout=$generation" >/dev/null || true
	;;
close)
	# 再作成済みなら stale な旧 workspace だけを閉じ、登録済みの新 workspace は保護する。
	close_workspaces "$exists" || exit 0
	;;
esac
