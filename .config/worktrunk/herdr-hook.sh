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
	timeout -k 1s 3s herdr "$@" 9>&- 2>/dev/null
}

# 未起動の通常操作では Git の path 解決や lock file の作成をしない。
status=$(herdr_cmd status server --json) || exit 0
jq -e '.running == true' <<<"$status" >/dev/null || exit 0

action=$1
primary=$(realpath -e -- "$2") || exit 0
checkout=$(realpath -m -- "$3") || exit 0
[[ "$checkout" != "$primary" ]] || exit 0
common=$(git -C "$primary" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
common=$(realpath -e -- "$common") || exit 0

# post-switch / post-remove は別々の background job。open と close を直列化し、
# lock 取得後に checkout を再確認して、遅れて起動した open が削除済みの表示を戻さないようにする。
mkdir -p "$common/wt"
exec 9>"$common/wt/herdr-sync.lock"
# 各 API 呼び出しに時間制限がある。background job の待機は制限せず、
# 複数削除や slow server でキューが長くなっても同期イベントを落とさない。
flock 9 || { echo 'worktrunk/herdr: could not acquire sync lock' >&2; exit 0; }

checkout_exists() {
	local root git_common
	[[ -d "$checkout" ]] || return 1
	root=$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null) || return 1
	git_common=$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
	[[ $(realpath -e -- "$root") == "$checkout" && $(realpath -e -- "$git_common") == "$common" ]]
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
			if [[ -n "$known" ]]; then
				[[ "$known" != "$generation" ]] || continue
			else
				panes=$(herdr_cmd pane list --workspace "$id") || return 1
				# 手動登録など識別情報がない場合は Linux の削除済み cwd を確認する。
				jq -e --arg path "$checkout" '
					any(.result.panes[]; [.cwd, .foreground_cwd][] |
						select(type == "string") | endswith(" (deleted)") and
						(. == ($path + " (deleted)") or startswith($path + "/")))
				' <<<"$panes" >/dev/null || continue
			fi
		fi
		herdr_cmd workspace close "$id" >/dev/null || return 1
	done <<<"$records"
}

# path が同じでも root inode / birth time が違えば別の checkout。
# ctime / mtime は通常のファイル編集でも変わるので識別情報には使わない。
# birth time の表示は locale / TZ によって変わらないよう固定する。
generation=''
if checkout_exists; then generation=$(LC_ALL=C TZ=UTC stat -c '%d:%i:%w' -- "$checkout") || exit 0; fi

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
	close_workspaces true || exit 0
	opened=$(herdr_cmd worktree open --workspace "$parent" --path "$checkout" --no-focus) || exit 0
	id=$(jq -er '.result.workspace.workspace_id' <<<"$opened") || exit 0
	herdr_cmd workspace report-metadata "$id" --source dotfiles-worktrunk \
		--token "dotfiles_wt_checkout=$generation" >/dev/null || true
	;;
close)
	# 再作成済みなら stale な旧 workspace だけを閉じ、登録済みの新 workspace は保護する。
	stale_only=false
	if checkout_exists; then stale_only=true; fi
	close_workspaces "$stale_only" || exit 0
	;;
esac
