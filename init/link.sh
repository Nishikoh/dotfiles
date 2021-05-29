#!/bin/bash -xeu
rm -f ~/.gitconfig
ln -s ~/dotfiles/gitconfig ~/.gitconfig
rm -f ~/.zshrc
ln -s ~/dotfiles/zshrc ~/.zshrc
rm -f ~/.vimrc
ln -s ~/dotfiles/vimrc ~/.vimrc