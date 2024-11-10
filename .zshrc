
ZSH_CONFIG_PATH=$(dirname $(readlink -f ~/.zshrc ))/zsh
for f in $ZSH_CONFIG_PATH/*; do
    echo read $f
    source $f
done

echo "done setup base zsh config"

echo "\nalias list"
alias
echo 

# TODO: setup argc completions
