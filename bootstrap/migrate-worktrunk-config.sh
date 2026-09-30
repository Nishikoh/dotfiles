#!/usr/bin/env bash
# PR の初期設定を適用済みの場合だけ、管理元の user-config symlink を外す。
# 実ファイルとユーザー独自のリンクは保持する。hook 設定は System config から読み込む。
set -euo pipefail
config="$HOME/.config/worktrunk/config.toml"
source=$(realpath -e -- "$1/.config/worktrunk/config.toml")
if [[ -L "$config" && $(realpath -m -- "$config") == "$source" ]]; then
	rm -- "$config"
fi
