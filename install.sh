#!/bin/bash -exu
echo $1

which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
if [ "$1" = "linux" ]; then
    PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
fi
brew bundle
