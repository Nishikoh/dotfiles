#!/bin/bash -xeu

# -eはエラー時にスクリプトが停止、-uは未定義変数利用時にスクリプトが停止
set -eu

# 本ファイルが存在するカレントディレクトリの絶対パスをカレントディレクトリを移動せず取得
cwd=$(dirname "${0}")
DOTFILES_PATH=$( (cd "${cwd}" && pwd))

# 正規表現で設定ファイルを取得し、シンボリックリンクを張る
for f in .??*; do
    # 除外リスト
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".gitignore" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue

    # シンボリックリンクを張る
    ln -snfv ${DOTFILES_PATH}/"${f}" ~/"${f}"
done
