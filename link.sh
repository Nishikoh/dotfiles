#!/bin/bash -xeu
# -eはエラー時にスクリプトが停止、-uは未定義変数利用時にスクリプトが停止
set -eu

# 本ファイルが存在するカレントディレクトリの絶対パスをカレントディレクトリを移動せず取得
cwd=$(dirname "${0}")
DOTFILES_PATH=$( (cd "${cwd}" && pwd))

# 正規表現で設定ファイルを取得し、シンボリックリンクを張る
for f in .??*; do
    # 除外リスト
    ([ "$f" = ".git" ] || \
    [ "$f" = ".gitignore" ] || \
    [ "$f" = ".DS_Store" ] || \
    [ "$f" = ".github" ] || \
    [ "$f" = ".latexmkrc" ] || \
    [ "$f" = ".config" ] || \
    [ "$f" = ".vscode-server" ]) && continue

    echo $f
    if [ ! -e ~/"$f" ] || diff -u ${DOTFILES_PATH}/"${f}" ~/"${f}"; then
    # シンボリックリンクを張る
    ln -snfv ${DOTFILES_PATH}/"${f}" ~/"${f}"
     continue
    fi
done
