#!/usr/bin/env bash
# mise bootstrap で新しいマシンをセットアップできることを Docker (Ubuntu, Arch) で確かめる。
#
# 実行: bash tests/test-mise-bootstrap.sh [ubuntu] [arch]   （引数なしなら両方）
#
# 環境変数:
#   SKIP_TOOLS=1  [tools] のインストールと bootstrap タスクを省く。
#                 mise install は GitHub API を多く呼ぶので、繰り返し試すときはこれを使う。
#   GITHUB_TOKEN  明示したときだけコンテナに渡し、mise が GitHub API を呼ぶときに使う。
#                 コンテナ内では第三者のインストールスクリプトも動くので、`gh auth token` などを自動では使わない。
#                 認証なしの API は 1 時間に 60 回までで、ツールまで含めた実行では足りないことがある。
#                 権限を何も付けないトークン (fine-grained PAT など) で十分。
#   MISE_VERSION  コンテナに入れる mise のバージョン (例: v2026.9.1)。未設定なら最新。
#                 指定と違うバージョンが入ったら失敗する。
#   REBUILD=1     ベースイメージと mise を取り直す (docker build --pull --no-cache)。
#                 指定しないとイメージのキャッシュが使われ、mise は最初にビルドしたときのバージョンのままになる。
#   KEEP=1        終了後もスナップショットを残し、コンテナに入って手で調べるための docker run コマンドを表示する。
#
# 判定の考え方:
#   - git に登録済み (stage 済みを含む) のファイルを、作業ツリーの内容 (未コミットの変更を含む) で git リポジトリにスナップショットし、
#     コンテナ内で `mise bootstrap --from <snapshot>` する。新しいマシンで GitHub から clone する手順と同じ流れになる。
#   - 1 回目の後に dotfiles / repos / packages が宣言どおりになっていること、zsh が起動できることを確かめる。
#   - clone 済みのリポジトリで 2 回目の `mise bootstrap` をしても失敗しない（冪等である）ことを確かめる。
#   - 以前の手順でセットアップしたマシンの状態を再現し、README の clone 手順 (--dry-run を含む) が通ることを確かめる。
set -euo pipefail

# git の hook などから呼ばれて GIT_DIR などが設定されていると、スナップショットの git init が
# 呼び出し元のリポジトリを再初期化してしまうので消しておく (tests/lefthook-dump.sh と同じ)
while IFS= read -r var; do unset "${var}"; done < <(git rev-parse --local-env-vars)

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${test_dir}/.." && pwd)"
source "$test_dir/docker-helpers.sh"

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
	targets=(ubuntu arch)
fi

# 値をコマンドラインに載せないよう、docker には変数名だけを渡す
token_env=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
	export GITHUB_TOKEN
	token_env=(-e GITHUB_TOKEN)
elif [[ "${SKIP_TOOLS:-}" != 1 ]]; then
	echo "warning: GITHUB_TOKEN が無いので、ツールのインストールで GitHub API のレート制限 (認証なしは 60 回/時) に当たることがある" >&2
fi

# 削除した以前のセットアップ (setup.sh / Argcfile.sh / bin_github.txt) をコードから参照していないこと (説明文の *.md は除く)
if git -C "${repo_dir}" grep --untracked -nE 'setup\.sh|Argcfile|bin_github' -- ':!tests/test-mise-bootstrap.sh' ':!*.md'; then
	echo "NG: 削除したファイルへの参照が残っています" >&2
	exit 1
fi

image_suffix="${MISE_VERSION:+-${MISE_VERSION}}"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mise-bootstrap-test.XXXXXX")"
# /src の所有者がコンテナのユーザーと異なるため safe.directory を設定する。~/.gitconfig は dotfiles で配置するので環境変数で渡す
docker_git_env=(-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*')

cleanup() {
	if [[ "${KEEP:-}" != 1 ]]; then
		rm -rf "${work_dir}"
		return
	fi
	echo
	echo "スナップショットを残しました: ${snapshot:-${work_dir}}"
	echo "コンテナに入って調べるには:"
	for target in "${targets[@]}"; do
		echo "  docker run --rm -it ${docker_git_env[*]@Q} -v '${snapshot:-${work_dir}/dotfiles}:/src:ro' 'dotfiles-bootstrap:${target}${image_suffix}' bash"
	done
	echo "  (コンテナ内で) mise bootstrap --from /src --from-dir ~/setup/dotfiles --yes --skip tools,task"
	echo "片付け: rm -rf '${work_dir}'"
}
trap cleanup EXIT

# グローバルの gitignore に左右されないよう、リポジトリの .gitignore だけを見てファイルを集める
snapshot="${work_dir}/dotfiles"
mkdir -p "${snapshot}"
# CI が checkout するのと同じく、git に登録済み (stage 済みを含む) のファイルだけを使う。
# 登録していないファイルは含めない (無視されている秘密情報などをコンテナに渡さないため)。新しいファイルは先に git add する。
# 作業ツリーで削除したファイル (stage していないもの) は --cached に残るので除く
(
	cd "${repo_dir}"
	git ls-files -z --cached |
		while IFS= read -r -d '' f; do
			if [[ -e "${f}" || -L "${f}" ]]; then printf '%s\0' "${f}"; fi
		done |
		tar --null -T - -cf -
) | tar -xf - -C "${snapshot}"
git -C "${snapshot}" init -q
# 集めたファイルはすべて登録済みのものなので、ignore に関係なくすべて入れる
git -C "${snapshot}" add --all --force
git -C "${snapshot}" -c user.name=test -c user.email=test@example.com commit -qm snapshot
chmod -R a+rX "${work_dir}"

skip_args=""
if [[ "${SKIP_TOOLS:-}" == 1 ]]; then
	skip_args="--skip tools,task"
fi

# コンテナ内の mise のバージョンを表示し、MISE_VERSION の指定どおりか確かめる
# shellcheck disable=SC2016 # コンテナ内で展開する
check_mise_version='
source /src/tests/docker-helpers.sh
check_mise_version || exit 1
'

# shellcheck disable=SC2016 # コンテナ内で展開する
container_script='
set -euo pipefail
dotfiles=~/setup/dotfiles

echo "::: 1st run: mise bootstrap --from"
mise bootstrap --from /src --from-dir "$dotfiles" --yes $SKIP_ARGS

echo "::: check dotfiles"
for f in .gitconfig .vimrc .zshrc .config/git/ignore .config/helix .config/lazygit .config/mise .config/starship.toml .config/yazi \
	.config/herdr/config.toml .config/worktrunk/herdr-hook.sh \
	.claude/settings.json .claude/hooks .claude/statusline-command.sh .claude/skills/dev-lsp; do
	test "$(readlink ~/"$f")" = "$dotfiles/$f" || { echo "NG: ~/$f -> $(readlink ~/"$f")"; exit 1; }
done

echo "::: check codex system config"
grep -qxF "writable_roots = [\"$HOME/.cache/\"]" /etc/codex/config.toml
test "$(stat -c %U:%a /etc/codex/config.toml)" = root:644
cmp "$dotfiles/.config/worktrunk/config.toml" /etc/xdg/worktrunk/config.toml
test "$(stat -c %U:%a /etc/xdg/worktrunk/config.toml)" = root:644
test ! -e ~/.config/worktrunk/config.toml

cd "$dotfiles"
echo "::: check status"
test -z "$(git status --porcelain)" || { git status --short; exit 1; }
mise dot status --missing
mise bootstrap repos status --missing
mise bootstrap packages status --missing
command -v zsh vim

if [[ -z "$SKIP_ARGS" ]]; then
	echo "::: check tools"
	mise bootstrap status --missing
	test -f ~/setup/argc-completions/completions/lh.sh
	# 生成物で argc-completions が dirty になると、次回の repos フェーズが失敗する
	test -z "$(git -C ~/setup/argc-completions status --porcelain)" || { git -C ~/setup/argc-completions status --short; exit 1; }
	# zsh/02path.zsh が無条件に読み込む
	test -f ~/.cargo/env
	# .zshrc を読み込んだ対話シェルで、mise と cargo のツールが使えること
	zsh -i -c "command -v starship cargo uv gh claude cpz rmz xcp pueue pueued ghalint github-comment argc terraform-target" </dev/null
	# codex が System 設定を読み込むこと (features.multi_agent = false は既定値の true と異なる)
	zsh -i -c "codex features list" </dev/null | grep -E "^multi_agent +.* false$"
	echo "::: Worktrunk / Herdr integration"
	mise exec -- bash tests/worktrunk-herdr-cases.sh
fi

# dot:add のテストは意図的に clone を変更するので、先に 2 回目と clean な状態を確認する。
echo "::: 2nd run: mise bootstrap (idempotent)"
mise bootstrap --yes $SKIP_ARGS
test -z "$(git status --porcelain)" || { git status --short; exit 1; }

echo "::: mise run dot:add で新しい設定をリポジトリに取り込める"
mkdir -p ~/.config/example && echo "enabled = true" >~/.config/example/example.conf
MISE_TASK_RUN_AUTO_INSTALL=false mise run dot:add ~/.config/example
test "$(readlink ~/.config/example)" = "$dotfiles/.config/example"
test -f "$dotfiles/.config/example/example.conf"
grep -xF "\"~/.config/example\" = { source = \".config/example\" }" mise.toml

echo "::: 別のチェックアウト (worktree など) で dot:add すると、そのチェックアウトに取り込まれ、main には触らない"
git clone -q /src ~/other
(
	cd ~/other
	mise trust --quiet --all
	mkdir -p ~/.config/example2 && echo "enabled = true" >~/.config/example2/example.conf
	MISE_TASK_RUN_AUTO_INSTALL=false mise run dot:add ~/.config/example2
	test "$(readlink ~/.config/example2)" = "$HOME/other/.config/example2"
	test -f ~/other/.config/example2/example.conf
	grep -xF "\"~/.config/example2\" = { source = \".config/example2\" }" mise.toml
)
test ! -e "$dotfiles/.config/example2"
! grep -F example2 "$dotfiles/mise.toml"

echo "::: dot:add 後の bootstrap でも追加した entry を配置できる"
mise bootstrap --yes $SKIP_ARGS
test "$(readlink ~/.config/example)" = "$dotfiles/.config/example"
test -f ~/.config/example/example.conf

echo "::: OK"
'

# WSL を WSL_DISTRO_NAME で模擬する。tools は各 OS の通常の実行で確かめているので省く
# shellcheck disable=SC2016 # コンテナ内で展開する
wsl_script='
set -euo pipefail
dotfiles=~/setup/dotfiles
export WSL_DISTRO_NAME=Ubuntu

echo "::: WSL: -E wsl なしの --from は、WSL 以外の設定をリンクしたことを検出して失敗する"
if mise bootstrap --from /src --from-dir "$dotfiles" --yes --skip tools,task 2>&1 | tee /tmp/out; then
	echo "NG: 失敗するはずが成功した"
	exit 1
fi
grep -F "mise -E wsl bootstrap" /tmp/out

echo "::: WSL: mise -E wsl bootstrap --from は WSL 用の設定をリンクする"
mise -E wsl bootstrap --from /src --from-dir "$dotfiles" --yes --skip tools,task
test "$(readlink ~/.config/herdr/config.toml)" = "$dotfiles/.config/herdr/config.wsl.toml"

echo "::: WSL: リポジトリ内では .miserc.toml が wsl 環境を選ぶので、-E なしでも WSL 用のまま"
cd "$dotfiles"
mise bootstrap --yes --skip tools,task
test "$(readlink ~/.config/herdr/config.toml)" = "$dotfiles/.config/herdr/config.wsl.toml"
echo "::: OK"
'

# 以前の手順 (Argcfile.sh) でセットアップしたマシンを再現し、README の clone 手順で bootstrap する
# shellcheck disable=SC2016 # コンテナ内で展開する
existing_script='
set -euo pipefail
dotfiles=~/setup/dotfiles

git clone -q /src "$dotfiles"
cd "$dotfiles"
mise trust --quiet --all
if [[ -z "$SKIP_ARGS" ]]; then
	echo "::: README の手順: clone して trust し、通常の --dry-run を実行する"
	mise bootstrap --dry-run
else
	echo "::: clone して trust し、tools/task を省いた --dry-run を実行する"
	mise bootstrap --dry-run $SKIP_ARGS
fi

echo "::: 既存マシン: 以前の手順の状態を用意する"
# 補完の生成物が残った argc-completions
git clone -q --depth 1 https://github.com/sigoden/argc-completions.git ~/setup/argc-completions
touch ~/setup/argc-completions/completions/lh.sh
# ~/.config/git がリポジトリへのディレクトリリンクで、他のツール (omarchy など) の config がリポジトリ側に書かれている
mkdir -p ~/.config
ln -s "$dotfiles/.config/git" ~/.config/git
echo "[user]" >"$dotfiles/.config/git/config"
# Worktrunk の user config と承認情報はマシン固有の実ファイルとして保持する。
mkdir -p ~/.config/worktrunk
echo "# local approvals" >~/.config/worktrunk/approvals.toml
echo "worktree-path = \"../local-{{ branch }}\"" >~/.config/worktrunk/config.toml

check_git_dir() {
	# リポジトリの ignore は普通のファイルのまま変わっていない
	test -f "$dotfiles/.config/git/ignore" && ! test -L "$dotfiles/.config/git/ignore"
	git -C "$dotfiles" diff --quiet -- .config/git/ignore
	# ~/.config/git は実ディレクトリになり、ignore だけがリポジトリへのリンク、config は移っている
	test -d ~/.config/git && ! test -L ~/.config/git
	test "$(readlink ~/.config/git/ignore)" = "$dotfiles/.config/git/ignore"
	test "$(cat ~/.config/git/config)" = "[user]"
	test -d ~/.config/worktrunk && ! test -L ~/.config/worktrunk
	test "$(cat ~/.config/worktrunk/approvals.toml)" = "# local approvals"
	test ! -L ~/.config/worktrunk/config.toml
	grep -qxF "worktree-path = \"../local-{{ branch }}\"" ~/.config/worktrunk/config.toml
	cmp "$dotfiles/.config/worktrunk/config.toml" /etc/xdg/worktrunk/config.toml
	test "$(readlink ~/.config/worktrunk/herdr-hook.sh)" = "$dotfiles/.config/worktrunk/herdr-hook.sh"
	test -f "$dotfiles/.config/worktrunk/config.toml" && ! test -L "$dotfiles/.config/worktrunk/config.toml"
	test -z "$(git -C "$dotfiles" status --porcelain)" || { git -C "$dotfiles" status --short; exit 1; }
}

echo "::: 既存マシン: bootstrap できる"
mise bootstrap --yes --skip tools,task
check_git_dir
mise bootstrap repos status --missing
mise dot status --missing

echo "::: 既存マシン: --force-dotfiles でもリポジトリのファイルを壊さない"
mise bootstrap --yes --skip tools,task --force-dotfiles
check_git_dir
grep -qxF "worktree-path = \"../local-{{ branch }}\"" ~/.config/worktrunk/config.toml
echo "::: OK"
'

for target in "${targets[@]}"; do
	echo "===== ${target} ====="
	image="dotfiles-bootstrap:${target}${image_suffix}"
	build_bootstrap_image "$target" "$repo_dir"
	docker run --rm \
		"${token_env[@]}" \
		-e SKIP_ARGS="${skip_args}" \
		-e EXPECT_MISE_VERSION="${MISE_VERSION:-}" \
		"${docker_git_env[@]}" \
		-v "${snapshot}:/src:ro" \
		"${image}" bash -c "${check_mise_version}${container_script}"

	echo "===== ${target} (WSL) ====="
	docker run --rm \
		"${docker_git_env[@]}" \
		-v "${snapshot}:/src:ro" \
		"${image}" bash -c "${wsl_script}"

	echo "===== ${target} (既存マシン / clone 手順) ====="
	docker run --rm \
		"${token_env[@]}" \
		-e SKIP_ARGS="${skip_args}" \
		"${docker_git_env[@]}" \
		-v "${snapshot}:/src:ro" \
		"${image}" bash -c "${existing_script}"
done
