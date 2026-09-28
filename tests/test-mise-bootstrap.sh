#!/usr/bin/env bash
# mise bootstrap で新しいマシンをセットアップできることを Docker (Ubuntu, Arch) で確かめる。
#
# 実行: bash tests/test-mise-bootstrap.sh [ubuntu] [arch]   （引数なしなら両方）
#
# 環境変数:
#   SKIP_TOOLS=1  [tools] のインストールと bootstrap タスクを省く。
#                 mise install は GitHub API を多く呼ぶので、繰り返し試すときはこれを使う。
#   GITHUB_TOKEN  mise が GitHub API を呼ぶときに使う。未設定なら `gh auth token` を使う。
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

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mise-bootstrap-test.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

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

# shellcheck disable=SC2016 # コンテナ内で展開する
container_script='
set -euo pipefail
dotfiles=~/setup/dotfiles

echo "::: 1st run: mise bootstrap --from"
mise bootstrap --from /src --from-dir "$dotfiles" --yes $SKIP_ARGS

echo "::: check dotfiles"
for f in .gitconfig .vimrc .zshrc .config/git/ignore .config/helix .config/lazygit .config/mise .config/starship.toml .config/yazi \
	.claude/settings.json .claude/hooks .claude/statusline-command.sh .claude/skills/dev-lsp; do
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

for target in "${targets[@]}"; do
	echo "===== ${target} ====="
	docker build -q --build-arg BASE="${target}" -t "dotfiles-bootstrap:${target}" "${repo_dir}" >/dev/null
	# /src の所有者がコンテナのユーザーと異なるため safe.directory を設定する。~/.gitconfig は dotfiles で配置するので環境変数で渡す
	docker run --rm \
		-e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
		-e SKIP_ARGS="${skip_args}" \
		-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
		-v "${snapshot}:/src:ro" \
		"dotfiles-bootstrap:${target}" bash -c "${container_script}"
done
