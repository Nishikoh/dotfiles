#!/bin/bash -exu

which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
brew update
brew bundle

pipx ensurepath
pipx completions
pipx install poetry

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
