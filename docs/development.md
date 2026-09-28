# 開発メモ

mise bootstrap の設定を変えるときに、Docker で確かめる手順と、これまでにつまずいた点をまとめる。
テストスクリプトの使い方 (環境変数) は [tests/test-mise-bootstrap.sh](../tests/test-mise-bootstrap.sh) 冒頭のコメントが正。

## 基本の流れ

```sh
# 設定を変えながら試す (ツールのインストールを省くので GitHub API を使わない)
SKIP_TOOLS=1 bash tests/test-mise-bootstrap.sh ubuntu
# 最後に一度だけ、ツールまで含めて両 OS で試す (GITHUB_TOKEN は明示したときだけコンテナに渡る)
GITHUB_TOKEN=... bash tests/test-mise-bootstrap.sh 2>&1 | tee /tmp/bootstrap-test.log
grep -E '^(=====|:::|NG)' /tmp/bootstrap-test.log   # 出力が多いので区切りの行だけ見る
```

- 失敗を手で調べるときは `KEEP=1` を付ける。スナップショットが残り、コンテナに入るための `docker run` コマンドが表示される
- **GitHub API のレート制限**: 認証なしは 1 時間に 60 回 (IP ごと) で、ツールまで含めた実行では足りずに失敗することがある。ツールまで含めるときは `GITHUB_TOKEN` を明示して渡す。コンテナ内では第三者のインストールスクリプトも動くので、テストスクリプトは `gh auth token` などを自動では使わない。権限を何も付けないトークンで十分。認証なしの残りは `curl -s https://api.github.com/rate_limit` で確認できる
- CI (`.github/workflows/setup.yml`) は Actions の `GITHUB_TOKEN` (`contents: read`) を明示して渡している

## mise のバージョン

- 必要な mise は **2026.9.8 以上**
  - 2026.9.1: bootstrap の hook で `{{config_root}}` が展開されず、bootstrap が失敗する
  - 2026.9.4〜9.7: bootstrap は通るが `mise dot` コマンドが無い (README の手順やテストで使う)
- テストのイメージはキャッシュされるので、mise は最初にビルドしたときのバージョンのまま使われる。新しい mise で試すには `REBUILD=1`、特定のバージョンで試すには `MISE_VERSION=v2026.9.8` を付ける
- ホストの mise はコンテナと別物。Docker で通っても、ホストで設定を読めるかは別に確かめる (作業ツリーで `MISE_TRUSTED_CONFIG_PATHS=$PWD mise config ls` など、書き込まないコマンドで)

## つまずいた点

- **グローバルの gitignore で新しいファイルが黙って除外される**: 古いグローバル ignore (`.*` や `*lefthook*`) が残っているマシンでは、`.miserc.toml` や `.config/` 配下の新しいファイルが `git add -A` で追加されない。コミット前に `git -c core.excludesFile=/dev/null status --short` と `git status --short` を見比べ、足りないものは `git add -f` する。テストのスナップショットはグローバル ignore を無視して作るので、テストが通ってもコミット漏れには気づけない
- **bootstrap の前にコンテナのホームにファイルを作らない**: `git config --global` で `~/.gitconfig` を作ると、dotfiles の配置と衝突する。git の設定は `GIT_CONFIG_COUNT` などの環境変数で渡す (テストスクリプト参照)
- **git の hook から呼ばれるスクリプトは `GIT_DIR` などを消してから git を使う**: git は hook の実行時に `GIT_DIR` などを設定する。これを引き継いだ `git init` が一時ディレクトリではなく呼び出し元のリポジトリを再初期化し、worktree から push したときに共有の設定へ `core.bare=true` が書かれて main の作業ツリーが使えなくなったことがある。`while IFS= read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)` で消す (tests/lefthook-dump.sh 参照)。直すときは `git -C <main のパス> config core.bare false`
- **リポジトリ内の `.config/mise/mise.toml` もプロジェクトの設定として読まれる**: clone しただけの状態では信頼されていないので、README の手順は `mise trust --all`。`--from` の後の hook ではパスを明示して trust する (`--from` の実行中は一時的に信頼されているので、`--all` は何も記録しない)
- **`--dry-run` は hook を実行しない**: 以前の手順の生成物が残った argc-completions は、除外を登録する pre-repos hook が動かないので `--dry-run` では「local changes」で止まる (実際の `mise bootstrap` は通る)
- **1 回目が通るだけでは足りない**: 2 回目の `mise bootstrap` と、clone したリポジトリに変更が残っていないことまで確かめる。タスクの生成物で argc-completions が dirty になり、2 回目の repos フェーズが失敗したことがある
- **Dockerfile の「素のマシン」の再現には意図がある**: パッケージリストの扱いや一般ユーザーで動かす理由は [Dockerfile](../Dockerfile) のコメントを参照
- **ツールの挙動は Docker で試す**: codex や herdr が設定ファイルをどう書き換えるかは、ホストではなく Docker で試す (ホストでは herdr のサーバーが動いていて、実際に使っている設定がある)。スクリプトをマウントしてツールを入れて実行する

  ```sh
  docker run --rm -v "$PWD/try.sh:/t.sh:ro" dotfiles-bootstrap:ubuntu \
    bash -c 'mise use -g herdr@latest && eval "$(mise activate bash --shims)" && bash /t.sh'
  ```

## WSL

- Docker では本物の WSL を試せない。テストは `WSL_DISTRO_NAME` で模擬している
- WSL の上で Docker を動かしても、コンテナからは通常 binfmt_misc (`WSLInterop`) が見えないので WSL ではない扱いになる。ガード (`bootstrap/check-wsl-dotfiles.sh`) の判定にカーネル名を使わないのはこのため
- miserc のテンプレートでは環境変数しか使えない (`exec()` や `read_file()` は展開されずに TOML の解析エラーになる)

## lefthook

- `lefthook run test` は `lefthook/*.yaml` を `lh` と同じく取り込んだ設定を検査する ([tests/lefthook-dump.sh](../tests/lefthook-dump.sh))
- worktree などで `lh` を実行しない。マシンごとの `.lefthook-local.yaml` が作られ、コミット時に `lefthook/*.yaml` の linter が動くようになる

## CI

- [.github/workflows/setup.yml](../.github/workflows/setup.yml) は `master` 向けの PR でしか自動で動かない。別のブランチをベースにした PR では手動で起動する

  ```sh
  gh workflow run setup.yml --ref <branch>
  gh run list --workflow setup.yml --branch <branch> --limit 1
  ```
