#!/usr/bin/env bash
# lefthook/*.yaml を lh (zsh/06func.zsh) と同じく extends で取り込んだ設定を出力する。
# .lefthook.yaml の test から使う。マシンごとの .lefthook-local.yaml が無い環境 (CI や別の worktree) でも同じ結果になる。
#
# 環境変数:
#   LEFTHOOK_DUMP_DIR  取り込む yaml のディレクトリ (既定: リポジトリの lefthook/)。取り込み失敗を試すときに使う
set -euo pipefail

# git は hook の実行時に GIT_DIR などを設定する。これを引き継ぐと、下の git init が一時ディレクトリではなく
# 呼び出し元のリポジトリを再初期化し (worktree からだと core.bare=true になり main の作業ツリーが壊れる)、
# lefthook dump も呼び出し元の設定を読んでしまう
while IFS= read -r var; do unset "${var}"; done < <(git rev-parse --local-env-vars)

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lefthook_dir="${LEFTHOOK_DUMP_DIR:-${repo_dir}/lefthook}"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/lefthook-dump.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

git -C "${work_dir}" init -q
printf 'extends:\n  - %s/*.yaml\n' "${lefthook_dir}" >"${work_dir}/.lefthook.yaml"
dump="$(cd "${work_dir}" && lefthook dump)"

# 取り込みに失敗すると lint / fix が無くなり、null を期待する検査が素通りしてしまうので、ここで失敗させる
for hook in lint fix; do
	if [[ "$(yq ".${hook}" <<<"${dump}")" == null ]]; then
		echo "lefthook dump に ${hook} がありません (取り込み元: ${lefthook_dir})" >&2
		exit 1
	fi
done

printf '%s\n' "${dump}"
