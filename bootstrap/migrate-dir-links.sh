#!/usr/bin/env bash
# dotfiles のリンクの単位 (ディレクトリごとか、ファイルごとか) が以前の手順と今の mise.toml で違うと、
# 既存のマシンで dotfiles の配置が失敗したり、リポジトリのファイルを壊したりするので、配置の前に今の単位に揃える。
# mise.toml の pre-dotfiles hook から、リポジトリのルートを引数にして呼ぶ。
set -euo pipefail

# git の hook などから呼ばれて GIT_DIR などが設定されていると、別のリポジトリを見てしまうので消す
while IFS= read -r var; do unset "${var}"; done < <(git rev-parse --local-env-vars)

repo="$(realpath "$1")"

# 以前の手順 (削除した argc のセットアップスクリプトの setup::config や、~/.config/* をまとめてリンクしていた頃の mise.toml) では、
# ~/.config 配下をディレクトリごとリポジトリにリンクしていた。今はファイル単位でリンクするものがあり、
# 親ディレクトリがリポジトリへのリンクのままだと、dotfiles の配置がリポジトリのファイル自身に向かう
# (--force-dotfiles では自分自身を指す symlink に置き換わり、中身が消える)。
# そうなっていれば、リンクを外して実ディレクトリに戻し、git で管理していないファイルだけをそこへ移す。
migrated_dirs=(.config/git)
for dir in "${migrated_dirs[@]}"; do
	link="${HOME}/${dir}"
	[[ -L "${link}" && "$(realpath "${link}")" == "$(realpath -m "${repo}/${dir}")" ]] || continue

	echo "migrate: ${link} をリポジトリへのリンクから実ディレクトリに戻す"
	rm "${link}" # リンク自体だけを消す (リンク先には触らない)
	mkdir -p "${link}"
	# 他のツールがリポジトリ側に書いたファイル (git で管理していないもの) だけを移す。管理しているファイルには触らない
	git -C "${repo}" ls-files -z --others -- "${dir}" | while IFS= read -r -d '' file; do
		mkdir -p "$(dirname "${HOME}/${file}")"
		mv "${repo}/${file}" "${HOME}/${file}"
		echo "migrate: ${file} を ${HOME}/${file} に移した"
	done
done

# 逆に、以前は実ディレクトリの中のファイルをリンクしていて、今はディレクトリごとリンクしているもの。
# 実ディレクトリが残っていると、mise は上書きを拒んで止まる。
# 中身がすべてリポジトリの同じ場所へのリンクなら、消しても失うものは無いので、リンクを消してディレクトリを空にし、mise にリンクを作らせる。
# ほかのもの (実ファイル、別の場所へのリンク、サブディレクトリ) が 1 つでもあれば触らない (mise が止まるので、人が中身を見て決める)
linked_dirs=(.config/mise)
for dir in "${linked_dirs[@]}"; do
	target="${HOME}/${dir}"
	[[ -d "${target}" && ! -L "${target}" ]] || continue

	entries=()
	only_repo_links=true
	while IFS= read -r -d '' entry; do
		name="${entry##*/}"
		# リンク切れでも失敗しないよう -m で解決する
		if [[ -L "${entry}" && "$(realpath -m "${entry}")" == "$(realpath -m "${repo}/${dir}/${name}")" ]]; then
			entries+=("${entry}")
		else
			only_repo_links=false
			break
		fi
	done < <(find "${target}" -mindepth 1 -maxdepth 1 -print0)
	"${only_repo_links}" || continue

	echo "migrate: ${target} を、中のファイルのリンクからディレクトリのリンクに替える"
	for entry in "${entries[@]}"; do
		rm "${entry}" # リンク自体だけを消す (リンク先には触らない)
	done
	rmdir "${target}" # 何か残っていれば失敗して止まる
done
