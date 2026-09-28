#!/bin/sh
# setup:completion (mise.toml) が argc-completions に生成するファイルを git から無視させる。
# 生成物で worktree が dirty になると、mise bootstrap の repos フェーズが「local changes」で失敗する。
# mise.toml の pre-repos / post-repos hook から呼ぶ。clone がまだ無ければ何もしない。
set -eu

repo="$HOME/setup/argc-completions"
[ -d "$repo/.git" ] || exit 0

exclude="$repo/.git/info/exclude"
mkdir -p "$(dirname "$exclude")"
grep -qxF completions/lh.sh "$exclude" 2>/dev/null || echo completions/lh.sh >>"$exclude"
