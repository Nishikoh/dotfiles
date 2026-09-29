#!/bin/sh
# WSL なのに wsl 環境が選ばれず (WSL_DISTRO_NAME が無い ssh 経由や、初回の --from)、
# WSL 以外の設定がリンクされたら失敗させる。mise.toml の post-dotfiles hook から呼ぶ。
# WSL の判定は bin/ssh と同じく binfmt_misc の WSLInterop も見る。
set -eu

is_wsl=
[ -n "${WSL_DISTRO_NAME:-}" ] && is_wsl=1
for f in /proc/sys/fs/binfmt_misc/WSLInterop*; do
	[ -e "$f" ] && is_wsl=1
done
[ -n "$is_wsl" ] || exit 0

case "$(readlink ~/.config/herdr/config.toml)" in
*/config.wsl.toml) ;;
*)
	echo "WSL ですが WSL 用の設定がリンクされていません。'mise -E wsl bootstrap' で再実行してください" >&2
	exit 1
	;;
esac
