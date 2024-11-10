
ZSH_CONFIG_PATH=$(dirname $(readlink -f ~/.zshrc ))/zsh
for f in $ZSH_CONFIG_PATH/*; do
    source $f
    # echo load $f
done

echo "done setup base zsh config"

echo "\nalias list"
alias
echo 

# TODO: setup argc completions
# argc completionsのgit補完が効かない時は補完作業用のディレクトリで一度`argc generate git`を実行する。
# ファイルが上書きされたままだと補完が弱いので、補完が聞くようになったらファイルを元に戻す
