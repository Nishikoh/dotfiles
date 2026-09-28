#!/usr/bin/env bash
# mise bootstrap で新しいマシンをセットアップできることを Docker (Ubuntu, Arch) で確かめる。
#
# 実行: bash tests/test-mise-bootstrap.sh [ubuntu] [arch]   （引数なしなら両方）
#
# 環境変数:
#   SKIP_TOOLS=1  [tools] のインストールと bootstrap タスクを省く。
#                 mise install は GitHub API を多く呼ぶので、繰り返し試すときはこれを使う。
#   GITHUB_TOKEN  mise が GitHub API を呼ぶときに使う。未設定なら `gh auth token` を使う。
#   MISE_VERSION  コンテナに入れる mise のバージョン (例: v2026.9.1)。未設定なら最新。
#                 指定と違うバージョンが入ったら失敗する。
#   REBUILD=1     ベースイメージと mise を取り直す (docker build --pull --no-cache)。
#                 指定しないとイメージのキャッシュが使われ、mise は最初にビルドしたときのバージョンのままになる。
#   KEEP=1        終了後もスナップショットを残し、コンテナに入って手で調べるための docker run コマンドを表示する。
#
# 判定の考え方:
#   - 作業ツリー（未コミットの変更を含む）を git リポジトリとしてスナップショットし、
#     コンテナ内で `mise bootstrap --from <snapshot>` する。新しいマシンで GitHub から clone する手順と同じ流れになる。
#   - 1 回目の後に dotfiles / repos / packages が宣言どおりになっていること、zsh が起動できることを確かめる。
#   - clone 済みのリポジトリで 2 回目の `mise bootstrap` をしても失敗しない（冪等である）ことを確かめる。
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${test_dir}/.." && pwd)"

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
	targets=(ubuntu arch)
fi

if [[ -z "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
	GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [[ -z "${GITHUB_TOKEN:-}" && "${SKIP_TOOLS:-}" != 1 ]]; then
	echo "warning: GITHUB_TOKEN がないため GitHub API のレート制限にかかる可能性があります" >&2
fi

image_suffix="${MISE_VERSION:+-${MISE_VERSION}}"
build_args=()
if [[ -n "${MISE_VERSION:-}" ]]; then
	build_args+=(--build-arg "MISE_VERSION=${MISE_VERSION}")
fi
if [[ "${REBUILD:-}" == 1 ]]; then
	build_args+=(--pull --no-cache)
fi

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
git -C "${repo_dir}" -c core.excludesFile=/dev/null ls-files -z --cached --others --exclude-standard |
	(cd "${repo_dir}" && tar --null -T - -cf -) | tar -xf - -C "${snapshot}"
git -C "${snapshot}" init -q
git -C "${snapshot}" -c core.excludesFile=/dev/null add -A
git -C "${snapshot}" -c user.name=test -c user.email=test@example.com commit -qm snapshot
chmod -R a+rX "${work_dir}"

skip_args=""
if [[ "${SKIP_TOOLS:-}" == 1 ]]; then
	skip_args="--skip tools,task"
fi

# コンテナ内の mise のバージョンを表示し、MISE_VERSION の指定どおりか確かめる
# shellcheck disable=SC2016 # コンテナ内で展開する
check_mise_version='
echo "::: mise $(mise --version)"
if [[ -n "${EXPECT_MISE_VERSION:-}" ]] && ! mise --version | grep -q "^${EXPECT_MISE_VERSION#v} "; then
	echo "NG: MISE_VERSION=${EXPECT_MISE_VERSION} を指定したが、入っているのは $(mise --version)"
	exit 1
fi
'

# shellcheck disable=SC2016 # コンテナ内で展開する
container_script='
set -euo pipefail
dotfiles=~/setup/dotfiles

echo "::: 1st run: mise bootstrap --from"
mise bootstrap --from /src --from-dir "$dotfiles" --yes $SKIP_ARGS

echo "::: check dotfiles"
for f in .gitconfig .vimrc .zshrc .config/git/ignore .config/helix .config/lazygit .config/mise .config/starship.toml .config/yazi \
	.config/herdr/config.toml .claude/settings.json .claude/hooks .claude/statusline-command.sh .claude/skills/dev-lsp; do
	test "$(readlink ~/"$f")" = "$dotfiles/$f" || { echo "NG: ~/$f -> $(readlink ~/"$f")"; exit 1; }
done
test -x ~/setup/bin/terraform-target

echo "::: check codex system config"
grep -qxF "writable_roots = [\"$HOME/.cache/\"]" /etc/codex/config.toml
test "$(stat -c %U:%a /etc/codex/config.toml)" = root:644

cd "$dotfiles"
echo "::: check status"
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
	# .zshrc を読み込んだ対話シェルで、mise と cargo のツールが使えること
	zsh -i -c "command -v starship cargo uv gh claude cpz rmz xcp pueue pueued ghalint github-comment argc" </dev/null
	# codex が System 設定を読み込むこと (features.multi_agent = false は既定値の true と異なる)
	zsh -i -c "codex features list" </dev/null | grep -E "^multi_agent +.* false$"
fi

echo "::: mise dot add で新しい設定をリポジトリに取り込める"
mkdir -p ~/.config/example && echo "enabled = true" >~/.config/example/example.conf
mise dot add -l --yes ~/.config/example
test "$(readlink ~/.config/example)" = "$dotfiles/.config/example"
test -f "$dotfiles/.config/example/example.conf"
grep -F "~/.config/example" mise.toml

echo "::: 2nd run: mise bootstrap (idempotent)"
mise bootstrap --yes $SKIP_ARGS
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

for target in "${targets[@]}"; do
	echo "===== ${target} ====="
	image="dotfiles-bootstrap:${target}${image_suffix}"
	docker build -q "${build_args[@]}" --build-arg BASE="${target}" -t "${image}" "${repo_dir}" >/dev/null
	docker run --rm \
		-e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
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
done
