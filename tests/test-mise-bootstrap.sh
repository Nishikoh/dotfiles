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
#   - 作業ツリー（未コミットの変更を含む）を git リポジトリとしてスナップショットし、
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
# 作業ツリーで削除したファイル (stage していないもの) は --cached に残るので除く
(
	cd "${repo_dir}"
	git -c core.excludesFile=/dev/null ls-files -z --cached --others --exclude-standard |
		while IFS= read -r -d '' f; do
			if [[ -e "${f}" || -L "${f}" ]]; then printf '%s\0' "${f}"; fi
		done |
		tar --null -T - -cf -
) | tar -xf - -C "${snapshot}"
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
	zsh -i -c "command -v starship cargo uv gh claude cpz rmz xcp pueue pueued ghalint github-comment argc terraform-target" </dev/null
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

# 以前の手順 (Argcfile.sh) でセットアップしたマシンを再現し、README の clone 手順で bootstrap する
# shellcheck disable=SC2016 # コンテナ内で展開する
existing_script='
set -euo pipefail
dotfiles=~/setup/dotfiles

echo "::: README の手順: clone して trust し、--dry-run する"
git clone -q /src "$dotfiles"
cd "$dotfiles"
mise trust --quiet --all
mise bootstrap --dry-run

echo "::: 既存マシン: 補完の生成物が残った argc-completions と、ダウンロード済みの terraform-target があっても bootstrap できる"
git clone -q --depth 1 https://github.com/sigoden/argc-completions.git ~/setup/argc-completions
touch ~/setup/argc-completions/completions/lh.sh
mkdir -p ~/setup/bin && printf "#!/bin/sh\n" >~/setup/bin/terraform-target
mise bootstrap --yes --skip tools,task
mise bootstrap repos status --missing
mise dot status --missing
echo "::: OK"
'

for target in "${targets[@]}"; do
	echo "===== ${target} ====="
	image="dotfiles-bootstrap:${target}${image_suffix}"
	docker build -q "${build_args[@]}" --build-arg BASE="${target}" -t "${image}" "${repo_dir}" >/dev/null
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
		"${docker_git_env[@]}" \
		-v "${snapshot}:/src:ro" \
		"${image}" bash -c "${existing_script}"
done
