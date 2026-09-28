# AGENTS.md

このリポジトリは dotfiles。mise bootstrap でマシンをセットアップする (手順は README.md、開発メモは docs/development.md)。

## 守ること

- 設定を変えたら Docker で確かめる。繰り返すときは `SKIP_TOOLS=1 bash tests/test-mise-bootstrap.sh`。ツールまで含めた実行は最後に一度だけ (GitHub API のレート制限があるため)。そのときの `GITHUB_TOKEN` は人間が明示して渡す (エージェントが `gh auth token` などで取得して渡さない)
- ツールの挙動の実験はホストでしない。Docker で行う (ホストの設定やサーバーは実際に使われている)
- 1 回目の bootstrap だけでなく、2 回目の実行と clone したリポジトリに変更が残っていないことまで確かめる
- コミット前に `git -c core.excludesFile=/dev/null status --short` と `git status --short` を見比べる。グローバルの gitignore で黙って除外されたファイルは `git add -f` する
- git の hook から呼ばれるスクリプトで git を使うときは、先に `git rev-parse --local-env-vars` の変数を消す (引き継いだ `GIT_DIR` で呼び出し元のリポジトリを壊したことがある)
- worktree で `lh` を実行したり `.lefthook-local.yaml` を作ったりしない
- `master` 以外をベースにした PR では CI が自動で動かないので `gh workflow run setup.yml --ref <branch>` で起動する
- 必要な mise は 2026.9.8 以上。ホストの mise はコンテナと別物なので、ホストで設定を読めるかは別に確かめる
