#!/usr/bin/env bash
# 以前の手順 (削除した argc のセットアップスクリプトの setup::config や、~/.config/* をまとめてリンクしていた頃の mise.toml) では、
# ~/.config 配下をディレクトリごとリポジトリにリンクしていた。今はファイル単位でリンクするものがあり、
# 親ディレクトリがリポジトリへのリンクのままだと、dotfiles の配置がリポジトリのファイル自身に向かう
# (--force-dotfiles では自分自身を指す symlink に置き換わり、中身が消える)。
# そうなっていれば、リンクを外して実ディレクトリに戻し、git で管理していないファイルだけをそこへ移す。
# mise.toml の pre-dotfiles hook から、リポジトリのルートを引数にして呼ぶ。
set -euo pipefail

# git の hook などから呼ばれて GIT_DIR などが設定されていると、別のリポジトリを見てしまうので消す
while IFS= read -r var; do unset "${var}"; done < <(git rev-parse --local-env-vars)

repo="$(realpath "$1")"

# 以前はディレクトリごとリンクしていて、今はファイル単位でリンクしているもの
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
