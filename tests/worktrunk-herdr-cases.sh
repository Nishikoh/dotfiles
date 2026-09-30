#!/usr/bin/env bash
# Docker 内専用。実際の wt と headless Herdr を使い、Git と表示の両方を確認する。
set -euo pipefail
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)
[[ -f /.dockerenv ]] || { echo 'Docker 内で実行してください' >&2; exit 1; }
for tool in wt herdr jq flock timeout; do command -v "$tool"; done
wt --version
herdr --version

work_dir=$(mktemp -d)
export HERDR_SESSION=dotfiles-integration
repo="$work_dir/repo space ' \$dollar"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/worktrunk"
hook="$config_dir/herdr-hook.sh"
sha256sum "$config_dir/config.toml" "$hook" >"$work_dir/config-before"
server_pid=''
cleanup() {
	herdr server stop >/dev/null 2>&1 || true
	[[ -z "$server_pid" ]] || wait "$server_pid" 2>/dev/null || true
	rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'echo "NG: line $LINENO" >&2; cat "$work_dir/wt.log" >&2' ERR

init_repo() {
	git init -q -b main "$1"
	git -C "$1" config user.name test
	git -C "$1" config user.email test@example.com
	git -C "$1" commit -qm init --allow-empty
}
init_repo "$repo"

run_wt() {
	if ! wt -C "$repo" "$@" -y >"$work_dir/wt.log" 2>&1; then
		cat "$work_dir/wt.log" >&2
		return 1
	fi
}
branch_path() {
	local field path=''
	while IFS= read -r -d '' field; do
		case "$field" in
		'worktree '*) path=${field#worktree } ;;
		"branch refs/heads/$1") printf '%s\n' "$path"; return ;;
		esac
	done < <(git -C "$repo" worktree list --porcelain -z)
	return 1
}
workspace_id() {
	herdr workspace list | jq -er --arg path "$1" '
		.result.workspaces[] | select(.worktree.checkout_path == $path) | .workspace_id
	'
}
is_open() { workspace_id "$1" >/dev/null 2>&1; }
is_closed() {
	local listing
	listing=$(herdr workspace list) || return 1
	jq -e --arg path "$1" 'any(.result.workspaces[]; .worktree.checkout_path == $path) | not' <<<"$listing" >/dev/null
}
path_removed() { [[ ! -e "$1" ]]; }
server_ready() { herdr workspace list >/dev/null 2>&1; }
wait_for() {
	local i
	for ((i=0; i<100; i++)); do
		if "$@"; then return 0; fi
		sleep 0.1
	done
	echo "NG: timeout: $*" >&2
	cat "$work_dir/wt.log" >&2 || true
	return 1
}
workspace_count() { herdr workspace list | jq '.result.workspaces | length'; }
focused_id() { herdr workspace list | jq -er '.result.workspaces[] | select(.focused) | .workspace_id'; }
sync_open() { wt -C "$1" hook post-switch herdr-open --foreground >/dev/null; }
sync_close() {
	wt -C "$repo" hook post-remove herdr-close --worktree-path="$1" --foreground >/dev/null
}

echo '::: Herdr 未起動でも作成・既存への切り替え・削除でき、サーバーを起動しない'
run_wt switch --create offline --no-cd
offline=$(branch_path offline)
run_wt switch offline --no-cd
sync_open "$offline"
run_wt remove offline --foreground
sync_close "$offline"
herdr status server | grep -q 'not running'

echo '::: 起動済みでも親リポジトリが未登録なら workspace を自動作成しない'
herdr server >"$work_dir/server.log" 2>&1 &
server_pid=$!
wait_for server_ready
count=$(workspace_count)
run_wt switch --create unregistered --no-cd
unregistered=$(branch_path unregistered)
sync_open "$unregistered"
[[ $(workspace_count) == "$count" ]]
run_wt remove unregistered --foreground

echo '::: 新規作成 (slash を含む branch、空白・引用符・ドルを含む path) / focus を奪わない'
parent=$(herdr workspace create --cwd "$repo" --focus | jq -er '.result.workspace.workspace_id')
run_wt switch --create feature/auth --no-cd
created=$(branch_path feature/auth)
wait_for is_open "$created"
[[ $(focused_id) == "$parent" ]]
id=$(workspace_id "$created")
count=$(workspace_count)

echo '::: 既存・同じ worktree・linked worktree から別の worktree / 重複登録しない'
run_wt switch feature/auth --no-cd
sync_open "$created"
[[ $(workspace_id "$created") == "$id" && $(workspace_count) == "$count" ]]
wt -C "$created" switch @ --no-cd -y >/dev/null
sync_open "$created"
[[ $(workspace_id "$created") == "$id" && $(workspace_count) == "$count" ]]
git -C "$repo" worktree add -q -b existing "$work_dir/existing checkout"
existing="$work_dir/existing checkout"
wt -C "$created" switch existing --no-cd -y >/dev/null
wait_for is_open "$existing"
[[ $(focused_id) == "$parent" ]]

echo '::: branch だけが既存の場合も新しい checkout を登録する'
git -C "$repo" branch branch-only
run_wt switch branch-only --no-cd
branch_only=$(branch_path branch-only)
wait_for is_open "$branch_only"

echo '::: primary 復帰と --no-hooks は workspace を増やさない'
count=$(workspace_count)
wt -C "$created" switch main --no-cd -y >/dev/null
sync_open "$repo"
[[ $(workspace_count) == "$count" ]]
run_wt switch --create no-hooks --no-cd --no-hooks
no_hooks=$(branch_path no-hooks)
[[ $(workspace_count) == "$count" ]]
run_wt remove no-hooks --foreground --no-hooks

echo '::: detached HEAD checkout の path による切り替え・削除'
detached="$work_dir/detached checkout"
git -C "$repo" worktree add -q --detach "$detached"
run_wt switch "$detached" --no-cd
wait_for is_open "$detached"
run_wt remove "$detached" --foreground
wait_for is_closed "$detached"
[[ ! -e "$detached" ]]

echo '::: dirty checkout の削除拒否で workspace を閉じない / force は成功後に閉じる'
touch "$existing/untracked"
if wt -C "$repo" remove existing --foreground -y >"$work_dir/wt.log" 2>&1; then
	echo 'NG: dirty checkout を削除できてしまった' >&2
	exit 1
fi
[[ -d "$existing" ]]
is_open "$existing"
run_wt remove existing --foreground --force
wait_for is_closed "$existing"
[[ ! -e "$existing" ]]

echo '::: 複数 checkout の削除 / primary と別リポジトリの workspace は残す'
other_repo="$work_dir/other repo"
init_repo "$other_repo"
other_id=$(herdr workspace create --cwd "$other_repo" --no-focus | jq -er '.result.workspace.workspace_id')
run_wt remove feature/auth branch-only --foreground
wait_for is_closed "$created"
wait_for is_closed "$branch_only"
herdr workspace get "$parent" >/dev/null
herdr workspace get "$other_id" >/dev/null

echo '::: project の pre-remove 失敗で workspace を閉じない'
run_wt switch --create rejected --no-cd
rejected=$(branch_path rejected)
wait_for is_open "$rejected"
mkdir -p "$rejected/.config"
printf 'pre-remove = "false"\n' >"$rejected/.config/wt.toml"
git -C "$rejected" add .config/wt.toml
git -C "$rejected" commit -qm 'reject removal'
if wt -C "$rejected" remove rejected --foreground -y >"$work_dir/wt.log" 2>&1; then
	echo 'NG: pre-remove 失敗でも削除できてしまった' >&2
	exit 1
fi
is_open "$rejected"
[[ -d "$rejected" ]]
git -C "$rejected" rm -q .config/wt.toml
git -C "$rejected" commit -qm 'allow removal'
run_wt remove rejected --foreground
wait_for is_closed "$rejected"

echo '::: 通常の background remove でも Git の削除後に workspace を閉じる'
run_wt switch --create background --no-cd
background=$(branch_path background)
wait_for is_open "$background"
run_wt remove background
wait_for is_closed "$background"
[[ ! -e "$background" ]]

echo '::: wt merge による自動削除でも workspace を閉じる'
run_wt switch --create merged --no-cd
merged=$(branch_path merged)
wait_for is_open "$merged"
echo merged >"$merged/merged.txt"
git -C "$merged" add merged.txt
git -C "$merged" commit -qm 'merge fixture'
(
	cd "$merged"
	eval "$(command wt config shell init bash)"
	wt merge main --no-commit --no-rebase -y >"$work_dir/wt.log" 2>&1
	[[ "$PWD" == "$repo" ]]
)
wait_for is_closed "$merged"
wait_for path_removed "$merged"
[[ $(cat "$repo/merged.txt") == merged ]]

echo '::: shell integration で cd してから現在の checkout を削除'
(
	cd "$repo"
	eval "$(command wt config shell init bash)"
	wt switch --create current -y >/dev/null
	current=$(branch_path current)
	[[ "$PWD" == "$current" ]]
	wait_for is_open "$current"
	wt remove --foreground -y >/dev/null
	[[ "$PWD" == "$repo" && ! -d "$current" ]]
	wait_for is_closed "$current"
)

echo '::: Herdr pane 内からの remove でも、checkout の削除を完了してから閉じる'
run_wt switch --create inside-pane --no-cd
inside=$(branch_path inside-pane)
wait_for is_open "$inside"
inside_id=$(workspace_id "$inside")
herdr pane run "$inside_id:p1" 'wt remove --foreground -y' >/dev/null
wait_for is_closed "$inside"
[[ ! -e "$inside" ]]

echo '::: 遅延した post-switch と remove の競合でも、削除済み workspace を再登録しない'
run_wt switch --create race --no-cd
race=$(branch_path race)
wait_for is_open "$race"
common=$(git -C "$repo" rev-parse --absolute-git-dir)
exec 8>"$common/wt/herdr-sync.lock"
flock 8
wt -C "$race" switch @ --no-cd -y >/dev/null
run_wt remove race --foreground
flock -u 8
wait_for is_closed "$race"
sync_open "$repo" # primary をスキップ
bash "$hook" open "$repo" "$race"
is_closed "$race"

echo '::: 遅延した post-remove が同じ path に再作成した checkout を閉じない'
run_wt switch --create recreated --no-cd
recreated=$(branch_path recreated)
wait_for is_open "$recreated"
flock 8
run_wt remove recreated --foreground
run_wt switch --create recreated --no-cd
flock -u 8
sync_close "$recreated"
wait_for is_open "$recreated"
run_wt remove recreated --foreground
wait_for is_closed "$recreated"

echo '::: CLI / jq が無くても Worktrunk の操作を妨げない'
wt_bin=$(command -v wt)
PATH=/usr/bin:/bin "$wt_bin" -C "$repo" switch --create missing --no-cd -y >/dev/null
missing=$(branch_path missing)
PATH=/usr/bin:/bin bash "$hook" open "$repo" "$missing"
PATH=/usr/bin:/bin "$wt_bin" -C "$repo" remove missing --foreground -y >/dev/null

echo '::: 不正 JSON と応答停止でも hook は成功扱いで有限時間で終了する'
mkdir "$work_dir/stub"
cat >"$work_dir/stub/herdr" <<'STUB'
#!/usr/bin/env bash
case "$HERDR_TEST_FAILURE" in
malformed) printf 'invalid json';;
hang) sleep 30;;
esac
STUB
chmod +x "$work_dir/stub/herdr"
run_wt switch --create errors --no-cd --no-hooks
errors=$(branch_path errors)
HERDR_TEST_FAILURE=malformed PATH="$work_dir/stub:$PATH" timeout 5s bash "$hook" open "$repo" "$errors" 2>/dev/null
HERDR_TEST_FAILURE=hang PATH="$work_dir/stub:$PATH" timeout 5s bash "$hook" open "$repo" "$errors"
run_wt remove errors --foreground

echo '::: 引き継いだ GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE を消して対象 repo を使う'
run_wt switch --create git-env --no-cd --no-hooks
git_env=$(branch_path git-env)
GIT_DIR="$other_repo/.git" GIT_WORK_TREE="$other_repo" GIT_INDEX_FILE="$work_dir/wrong-index" \
	bash "$hook" open "$repo" "$git_env"
is_open "$git_env"
[[ ! -e "$work_dir/wrong-index" ]]
echo '::: 別の named session を指定しても元の session に登録しない'
herdr workspace close "$(workspace_id "$git_env")" >/dev/null
HERDR_SESSION=unavailable bash "$hook" open "$repo" "$git_env"
is_closed "$git_env"
run_wt remove git-env --foreground
wait_for is_closed "$git_env"

echo '::: bare repo では Herdr の登録を増やさない'
git clone -q --bare "$repo" "$work_dir/bare.git"
bare_count=$(workspace_count)
wt -C "$work_dir/bare.git" switch --create bare-feature --no-cd -y >/dev/null
sync_open "$work_dir/bare.git.bare-feature"
[[ $(workspace_count) == "$bare_count" ]]

echo '::: 全 fixture の Git checkout が clean / 管理中の設定は未変更'
[[ -z $(git -C "$repo" status --porcelain) && -z $(git -C "$other_repo" status --porcelain) ]]
[[ -z $(git -C "$repo" diff) ]]
sha256sum "$config_dir/config.toml" "$hook" >"$work_dir/config-after"
[[ $(cat "$work_dir/config-before") == $(cat "$work_dir/config-after") ]]
echo '::: Worktrunk / Herdr OK'
