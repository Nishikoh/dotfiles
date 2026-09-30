#!/usr/bin/env bash
# Worktrunk が Git の lifecycle を管理し、起動済み Herdr の表示を best effort で同期する。
set -euo pipefail

# git hook 経由で起動しても、呼び出し元の GIT_DIR 等で別の checkout を参照しない。
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

[[ $# == 3 && ( $1 == open || $1 == close ) ]] || exit 0
for tool in herdr jq flock timeout; do
	command -v "$tool" >/dev/null 2>&1 || exit 0
done

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
flock -w 10 9 || exit 0

herdr_cmd() {
	# 未起動時にサーバーを開始しない API コマンドだけを使う。応答が止まっても待ち続けない。
	timeout -k 1s 3s herdr "$@" 2>/dev/null
}

checkout_exists() {
	local root git_common
	[[ -d "$checkout" ]] || return 1
	root=$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null) || return 1
	git_common=$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
	[[ $(realpath -e -- "$root") == "$checkout" && $(realpath -e -- "$git_common") == "$common" ]]
}

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
	herdr_cmd worktree open --workspace "$parent" --path "$checkout" --no-focus >/dev/null || true
	;;
close)
	# remove 直後に同じパスで作り直した checkout は閉じない。
	checkout_exists && exit 0
	listing=$(herdr_cmd workspace list) || exit 0
	ids=$(jq -er --arg path "$checkout" --arg repo "$common" '
		.result.workspaces[] | select(.worktree.is_linked_worktree == true and
			.worktree.checkout_path == $path and .worktree.repo_key == $repo) | .workspace_id
	' <<<"$listing") || exit 0
	while IFS= read -r id; do
		herdr_cmd workspace close "$id" >/dev/null || true
	done <<<"$ids"
	;;
esac
