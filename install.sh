#!/bin/bash -exu

curl -fsSL https://get.jetify.com/devbox | bash
eval "$(devbox global shellenv)"
# TODO latest config
devbox global pull https://gist.githubusercontent.com/Nishikoh/c58e4963b7abac7d06574360a1cd653b/raw/5f61b0294e6a2481e4078f43b3a70e21b571268d/devbox.json

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
#cargo install cargo-binstall
#cargo binstall cpz
#cargo binstall rmz

#cargo binstall xcp

#which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
#brew update
#brew bundle


#echo "export PATH=$PATH:/home/linuxbrew/.linuxbrew/bin/" >> ~/.bashrc
