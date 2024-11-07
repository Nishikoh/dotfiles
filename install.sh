#!/bin/bash -exu

curl -fsSL https://get.jetify.com/devbox | bash
eval "$(devbox global shellenv)"
devbox global pull https://github.com/Nishikoh/devbox.git

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

# TODO: argc-completion
# TODO gh-copilot

