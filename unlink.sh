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
    # シンボリックリンクを削除
    if [ -L ~/"${f}" ] ; then 
    echo $f
      unlink ~/"${f}"
    fi
done
