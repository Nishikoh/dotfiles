#!/usr/bin/env bash
# Docker 内専用。実際の wt と headless Herdr を使い、Git と表示の両方を確認する。
set -euo pipefail
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)
[[ -f /.dockerenv ]] || { echo 'Docker 内で実行してください' >&2; exit 1; }
for tool in wt herdr jq flock timeout; do command -v "$tool"; done
wt --version
herdr --version

work_dir=$(realpath -e -- "$(mktemp -d)")
export HERDR_SESSION=dotfiles-integration
repo="$work_dir/repo space ' \$dollar"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/worktrunk"
hook="$HOME/.config/worktrunk/herdr-hook.sh"
managed_config=${WORKTRUNK_SYSTEM_CONFIG_PATH:-/etc/xdg/worktrunk/config.toml}
sha256sum "$managed_config" "$hook" >"$work_dir/config-before"
server_pid=''
descendant_pid=''
cleanup() {
	if [[ -n "$descendant_pid" ]]; then kill "$descendant_pid" 2>/dev/null || true; fi
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

echo '::: Worktrunk の user config 更新は System config と管理元を変更しない'
printf '[commit-generation]\ncommand = "echo fixture"\n' >"$config_dir/config.toml"
wt config update -y >/dev/null
grep -qxF '[commit.generation]' "$config_dir/config.toml"
[[ ! -L "$config_dir/config.toml" ]]
sha256sum "$managed_config" "$hook" >"$work_dir/config-after"
[[ $(cat "$work_dir/config-before") == $(cat "$work_dir/config-after") ]]

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
file_exists() { [[ -f "$1" ]]; }
workspace_gone() { ! herdr workspace get "$1" >/dev/null 2>&1; }
has_generation() {
	herdr workspace get "$1" | jq -e '.result.workspace.tokens.dotfiles_wt_checkout | length > 0' >/dev/null
}
pane_at() {
	herdr pane get "$1:p1" | jq -e --arg path "$2" '.result.pane.cwd == $path' >/dev/null
}
pane_git_works() {
	local id=$1 marker="$work_dir/pane-git-$1"
	herdr pane run "$id:p1" "git status --porcelain > /dev/null && touch '$marker'" >/dev/null
	wait_for file_exists "$marker"
}

# production の hook 本文に、開始と終了の marker だけを追加する。
# この config を使う invocation では System config を外し、hook を二重に実行しない。
sed -e 's/bash "/touch "$HERDR_TEST_STARTED"; bash "/' \
	-e 's/ || true/ || true; touch "$HERDR_TEST_DONE"/' \
	"$managed_config" >"$work_dir/tracked-config.toml"
tracked_wt() {
	local name=$1
	shift
	HERDR_TEST_STARTED="$work_dir/$name.started" HERDR_TEST_DONE="$work_dir/$name.done" \
		WORKTRUNK_SYSTEM_CONFIG_PATH=/dev/null WORKTRUNK_CONFIG_PATH="$work_dir/tracked-config.toml" \
		wt "$@" -y >"$work_dir/wt.log" 2>&1
}

echo '::: Herdr 未起動でも作成・既存への切り替え・削除でき、サーバーを起動しない'
run_wt switch --create offline --no-cd
offline=$(branch_path offline)
run_wt switch offline --no-cd
sync_open "$offline"
run_wt remove offline --foreground
sync_close "$offline"
herdr status server | grep -q 'not running'
[[ ! -e "$repo/.git/wt/herdr-sync.lock" ]]

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
echo '::: XDG_CONFIG_HOME を変更しても mise dot の配置先から hook を実行する'
socket=$(herdr status server --json | jq -er '.socket')
mkdir -p "$work_dir/xdg-alt"
XDG_CONFIG_HOME="$work_dir/xdg-alt" HERDR_SOCKET_PATH="$socket" \
	wt -C "$repo" switch --create xdg --no-cd -y >"$work_dir/wt.log" 2>&1
xdg=$(branch_path xdg)
wait_for is_open "$xdg"
XDG_CONFIG_HOME="$work_dir/xdg-alt" HERDR_SOCKET_PATH="$socket" \
	wt -C "$repo" remove xdg --foreground -y >"$work_dir/wt.log" 2>&1
wait_for is_closed "$xdg"
echo '::: 手動で symlink 経由で開いた checkout も実パスの metadata で削除できる'
run_wt switch --create alias-path --no-cd --no-hooks
alias_path=$(branch_path alias-path)
ln -s "$alias_path" "$work_dir/checkout-alias"
herdr worktree open --cwd "$repo" --path "$work_dir/checkout-alias" --no-focus |
	jq -e --arg path "$alias_path" '.result.workspace.worktree.checkout_path == $path' >/dev/null
run_wt remove alias-path --foreground
wait_for is_closed "$alias_path"

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
common=$(realpath -e -- "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)")
exec 8>"$common/wt/herdr-sync.lock"
flock 8
tracked_wt race-open -C "$race" switch @ --no-cd
wait_for file_exists "$work_dir/race-open.started"
run_wt remove race --foreground
flock -u 8
wait_for file_exists "$work_dir/race-open.done"
wait_for is_closed "$race"
sync_open "$repo" # primary をスキップ
bash "$hook" open "$repo" "$race"
is_closed "$race"

echo '::: 再作成後の post-remove → post-switch は古い cwd の workspace を置き換える'
run_wt switch --create recreated --no-cd
recreated=$(branch_path recreated)
wait_for is_open "$recreated"
old_id=$(workspace_id "$recreated")
wait_for has_generation "$old_id"
# サブディレクトリにいる pane も、checkout の世代が変わったら古い workspace として閉じる。
herdr pane run "$old_id:p1" 'mkdir nested; cd nested' >/dev/null
wait_for pane_at "$old_id" "$recreated/nested"
flock 8
tracked_wt recreated-close -C "$repo" remove recreated --foreground
wait_for file_exists "$work_dir/recreated-close.started"
# close だけを先に完了させ、古い shell を残さないことを検査する。
run_wt switch --create recreated --no-cd --no-hooks
flock -u 8
wait_for file_exists "$work_dir/recreated-close.done"
wait_for is_closed "$recreated"
workspace_gone "$old_id"
sync_open "$recreated"
fresh_id=$(workspace_id "$recreated")
[[ "$fresh_id" != "$old_id" ]]
pane_git_works "$fresh_id"

echo '::: checkout が同じなら、pane の cwd の子ディレクトリを消しても workspace を閉じない'
herdr pane run "$fresh_id:p1" 'mkdir scratch; cd scratch; rmdir ../scratch' >/dev/null
wait_for pane_at "$fresh_id" "$recreated/scratch (deleted)"
sync_open "$recreated"
[[ $(workspace_id "$recreated") == "$fresh_id" ]]
printf -v restore_cwd 'cd %q' "$recreated"
herdr pane run "$fresh_id:p1" "$restore_cwd" >/dev/null
wait_for pane_at "$fresh_id" "$recreated"

echo '::: 識別情報のない手動登録の workspace も、子ディレクトリの削除では閉じず、checkout の削除後は置き換える'
manual_open() {
	herdr worktree open --workspace "$parent" --path "$1" --no-focus | jq -er '.result.workspace.workspace_id'
}
pane_deleted() {
	herdr pane get "$1:p1" | jq -e '.result.pane.cwd | endswith(" (deleted)")' >/dev/null
}
run_wt switch --create manual --no-cd --no-hooks
manual=$(branch_path manual)
manual_id=$(manual_open "$manual")
if has_generation "$manual_id"; then echo 'NG: 手動登録に識別情報がある' >&2; exit 1; fi
herdr pane run "$manual_id:p1" 'mkdir scratch; cd scratch; rmdir ../scratch' >/dev/null
wait_for pane_at "$manual_id" "$manual/scratch (deleted)"
sync_open "$manual"
[[ $(workspace_id "$manual") == "$manual_id" ]]
printf -v restore_cwd 'cd %q' "$manual"
herdr pane run "$manual_id:p1" "$restore_cwd" >/dev/null
wait_for pane_at "$manual_id" "$manual"
# wt remove は checkout を .git/wt/trash に移してから削除する。
run_wt remove manual --foreground --no-hooks
wait_for pane_deleted "$manual_id"
run_wt switch --create manual --no-cd --no-hooks
sync_open "$manual"
workspace_gone "$manual_id"
pane_git_works "$(workspace_id "$manual")"
run_wt remove manual --foreground
wait_for is_closed "$manual"
# git worktree remove は checkout をその場で削除する。
git -C "$repo" worktree add -q -b manual-git "$manual"
manual_id=$(manual_open "$manual")
git -C "$repo" worktree remove "$manual"
wait_for pane_at "$manual_id" "$manual (deleted)"
git -C "$repo" worktree add -q "$manual" manual-git
sync_open "$manual"
workspace_gone "$manual_id"
pane_git_works "$(workspace_id "$manual")"
run_wt remove manual-git --foreground
wait_for is_closed "$manual"

echo '::: 再作成後の post-switch → post-remove は新しい workspace を閉じない'
run_wt remove recreated --foreground --no-hooks
run_wt switch --create recreated --no-cd --no-hooks
sync_open "$recreated"
new_id=$(workspace_id "$recreated")
[[ "$new_id" != "$fresh_id" ]]
workspace_gone "$fresh_id"
sync_close "$recreated" # 遅れて到着した旧 checkout の post-remove
[[ $(workspace_id "$recreated") == "$new_id" ]]
pane_git_works "$new_id"
[[ $(focused_id) == "$parent" ]]
run_wt remove recreated --foreground
wait_for is_closed "$recreated"

echo '::: herdr のみ欠落 / jq のみ欠落をそれぞれ確認する'
wt_bin=$(command -v wt)
mkdir "$work_dir/without-herdr" "$work_dir/without-jq"
for tool in bash sh git realpath mkdir flock timeout; do
	ln -s "$(command -v "$tool")" "$work_dir/without-herdr/$tool"
	ln -s "$(command -v "$tool")" "$work_dir/without-jq/$tool"
done
ln -s "$(command -v jq)" "$work_dir/without-herdr/jq"
cat >"$work_dir/without-jq/herdr" <<'STUB'
#!/usr/bin/env bash
printf called >"$HERDR_TEST_CALLED"
exit 1
STUB
chmod +x "$work_dir/without-jq/herdr"
PATH="$work_dir/without-herdr" "$wt_bin" -C "$repo" switch --create missing --no-cd -y >/dev/null
missing=$(branch_path missing)
PATH="$work_dir/without-herdr" bash "$hook" open "$repo" "$missing"
HERDR_TEST_CALLED="$work_dir/unexpected-herdr-call" PATH="$work_dir/without-jq" bash "$hook" open "$repo" "$missing"
[[ ! -e "$work_dir/unexpected-herdr-call" ]]
PATH="$work_dir/without-herdr" "$wt_bin" -C "$repo" remove missing --foreground -y >/dev/null

echo '::: slow Herdr への複数 close が 10 秒以上待ってもイベントを落とさない'
mkdir "$work_dir/slow-cli"
cat >"$work_dir/slow-cli/herdr" <<'STUB'
#!/usr/bin/env bash
sleep 1
exec "$HERDR_TEST_REAL_CLI" "$@"
STUB
chmod +x "$work_dir/slow-cli/herdr"
queued_paths=()
queued_branches=()
for i in {1..8}; do
	run_wt switch --create "queued-$i" --no-cd --no-hooks
	path=$(branch_path "queued-$i")
	queued_paths+=("$path")
	queued_branches+=("queued-$i")
	sync_open "$path"
done
run_wt remove "${queued_branches[@]}" --foreground --no-hooks
pids=()
for path in "${queued_paths[@]}"; do
	HERDR_TEST_REAL_CLI=$(command -v herdr) PATH="$work_dir/slow-cli:$PATH" \
		timeout 35s bash "$hook" close "$repo" "$path" &
	pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
for path in "${queued_paths[@]}"; do is_closed "$path"; done

echo '::: 不正 JSON と応答停止でも hook は成功扱いで有限時間で終了する'
mkdir "$work_dir/stub"
cat >"$work_dir/stub/herdr" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == status ]]; then exec "$HERDR_TEST_REAL_CLI" "$@"; fi
case "$HERDR_TEST_FAILURE" in
malformed) printf 'invalid json';;
hang) sleep 30;;
descendant)
	setsid sleep 30 </dev/null >/dev/null 2>&1 &
	printf '%s' "$!" >"$HERDR_TEST_DESCENDANT_PID"
	sleep 30
	;;
esac
STUB
chmod +x "$work_dir/stub/herdr"
run_wt switch --create errors --no-cd --no-hooks
errors=$(branch_path errors)
real_cli=$(command -v herdr)
HERDR_TEST_REAL_CLI="$real_cli" HERDR_TEST_FAILURE=malformed PATH="$work_dir/stub:$PATH" timeout 6s bash "$hook" open "$repo" "$errors" 2>/dev/null
HERDR_TEST_REAL_CLI="$real_cli" HERDR_TEST_FAILURE=hang PATH="$work_dir/stub:$PATH" timeout 6s bash "$hook" open "$repo" "$errors"

echo '::: timeout を生き延びた子孫プロセスは repo の lock を保持しない'
HERDR_TEST_REAL_CLI="$real_cli" HERDR_TEST_FAILURE=descendant HERDR_TEST_DESCENDANT_PID="$work_dir/descendant-pid" \
	PATH="$work_dir/stub:$PATH" timeout 6s bash "$hook" open "$repo" "$errors"
descendant_pid=$(cat "$work_dir/descendant-pid")
kill -0 "$descendant_pid"
# 子孫が生きている間に、別プロセスから同じ lock を取得できることを確認する。
flock -n "$common/wt/herdr-sync.lock" true
timeout 6s bash "$hook" open "$repo" "$errors"
is_open "$errors"
kill "$descendant_pid"
descendant_pid=''
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
sha256sum "$managed_config" "$hook" >"$work_dir/config-after"
[[ $(cat "$work_dir/config-before") == $(cat "$work_dir/config-after") ]]
echo '::: Worktrunk / Herdr OK'
