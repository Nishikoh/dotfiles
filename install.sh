#!/bin/bash -exu

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
cargo install cargo-binstall
cargo install cpz
cargo install rmz
cargo binstall fcp

cargo install xcp
#cargo install typos

which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
brew update
brew bundle

curl -sSf https://rye-up.com/get | RYE_INSTALL_OPTION="--yes" bash

echo "export PATH=$PATH:/home/linuxbrew/.linuxbrew/bin/" >> ~/.bashrc
