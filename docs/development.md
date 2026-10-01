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

- 新しく作ったファイルは、テストの前に `git add` する (スナップショットは git に登録済みのファイルだけで作る)
- 失敗を手で調べるときは `KEEP=1` を付ける。スナップショットが残り、コンテナに入るための `docker run` コマンドが表示される
- **GitHub API のレート制限**: 認証なしは 1 時間に 60 回 (IP ごと) で、ツールまで含めた実行では足りずに失敗することがある。ツールまで含めるときは `GITHUB_TOKEN` を明示して渡す。コンテナ内では第三者のインストールスクリプトも動くので、テストスクリプトは `gh auth token` などを自動では使わない。権限を何も付けないトークンで十分。認証なしの残りは `curl -s https://api.github.com/rate_limit` で確認できる
- CI (`.github/workflows/setup.yml`) は Actions の `GITHUB_TOKEN` (`contents: read`) を明示して渡している

Worktrunk / Herdr の変更では、トークンなしの最小検証として
`bash tests/test-worktrunk-herdr.sh` を使える (引数で `ubuntu` / `arch` を指定可能)。
実際の CLI と headless Herdr server で、作成・切り替え・削除・merge・focus・削除拒否・
hook の実行順の競合・依存ツール欠落・応答停止を確認する。ツール取得は Docker build のキャッシュで再利用する。
`REBUILD=1` で base image / mise / ツールを取り直し、`MISE_VERSION=v...` で mise を指定できる。
競合テストは hook の開始・完了 marker を待ってから検査する。同じパスの再作成では古い workspace の終了と
新しい pane の cwd からの `git status` を確認し、登録と削除の両方の順序を検証する。
Herdr の pane 内の操作は、pane で `wt config shell init bash` と `herdr-shell.sh` を読み込み、`herdr pane run` で人間と同じように実行する。
`wt` は cd 先を `WORKTRUNK_DIRECTIVE_CD_FILE` に書き、shell の関数が cd する。
`herdr-shell.sh` はこの cd 先を受け取り、引数を解析せずに `herdr-hook.sh focus` で workspace を focus する。
focus は対話中の shell を待たせないよう lock の待機を 5 秒に制限し、失敗したら cd する。
`wt` はすでにその worktree の中にいると cd 先を書かないので、同じ workspace 内の移動は手動で別の worktree に cd してから確認する。

削除の判定は workspace の worktree metadata で候補を探し、pane ごとに process-info を見る。
shell だけが foreground にいて、shell の session に他のプロセスが無い pane を待機中とし、
それ以外 (エージェント、エディタ、`sleep`、background job) は閉じない。
Herdr は pane を閉じるとき、その pane の session のプロセスを nohup や SIGHUP の無視に関係なく終了させ、
別 session (`setsid`) のものだけが残ることを Docker で確認した。
Worktrunk の background 削除と post-* hook は `wt` を実行した pane の session で動くので、
操作元の pane を早く閉じると trash の削除が途中で止まる (Ubuntu では間に合い、Arch で再現した)。
そこで close は `setsid -w` で自分を別 session に移し、操作元の pane の session に
自分と祖先 (hook runner) 以外のプロセスが無くなるまで待つ。session は `/proc/<pid>/stat` から読む。
`wt merge` などの background 削除は、Git の登録を外した後、ディレクトリが残っている間に post-remove を始める。
そのため削除済みかどうかはディレクトリではなく Git の登録 (`herdr worktree list`) で判定する。
post-remove は `wt` の終了前に始まるので、操作元 `HERDR_PANE_ID` の foreground に `wt` か focus が残っている間、
または session に Worktrunk のプロセスが残っている間は、lock を取らずに最大 60 秒待つ。
lock を取ってから待つと、wrapper の focus が lock の待機で時間切れになる。エージェントが `wt` を実行した場合は待たない。
同じパスに再登録されている場合 (遅れて届いた post-remove) と post-switch の前処理では、削除済みの場所の pane だけを閉じる。
pane の `/proc/<pid>/cwd` の readlink を process-info の cwd と照合し、
checkout の子ディレクトリにいれば生存する祖先を root まで辿って device/inode を比較する。
idle shell の cwd は、poll のキャッシュである pane get より同期取得の process-info を優先する。
ここで比較するのは同時に存在する directory object であり、inode を永続的な世代 ID として保存しない。
子ディレクトリだけの削除では root が一致するため保護し、checkout 全体の再作成では古い root と異なるため置き換える。
`(deleted)` の cwd と `.git/wt/trash/` の中は削除途中の checkout なので、どの worktree のものかは区別しない
(以前は trash の名前 `<basename>-<epoch>` で対象を特定していたが、同じ basename の別配置で判定できなかった)。
stat の前後で cwd を照合し、close 直前にも pane と現在の root を再確認する。
ただし Herdr の取得と close は別 API なので、最後の確認直後の cd まで atomic に保護するものではない。
最後の pane close は Herdr が workspace を終了する。別の場所の pane だけを含む workspace が dedup で再利用された場合は、
現在の checkout に属する pane がなければ `--no-focus` で復帰先を追加し、繰り返し switch で増殖させない。
実行中の pane や状態を確認できない pane がある場合は、起動直後の shell かもしれないので追加しない。
Git の登録が無い linked worktree の workspace (孤立) は、同じリポジトリの次の同期で削除済みの場所の pane だけ閉じる。
`wt step relocate` は hook を実行しない。次の `worktree open` で Herdr が pane の場所から既存の workspace を再利用し、
checkout_path を更新することを Docker で確認した。
Linux の proc が利用できない場合は古い pane を保護する。Herdr と hook の process namespace が違う場合も
cwd の照合に成功しない限り終了しない。
lock の保持中の herdr / git / filesystem の操作にはすべて時間制限を設け、lock の待機は制限しない。
filesystem 操作も lock の fd を継承させず、TERM の後に KILL する。カーネル内で応答不能になった I/O の回復までは保証しない。
System 設定の hook は `$HOME/.config/worktrunk/herdr-hook.sh` が無いユーザー (sudo の root など) ではスキップする。
herdr の欠落と jq の欠落は、それぞれ専用の PATH で検証する。
bootstrap の full 実行と CI では、配置した設定を使って同じケースを実行する。
`dot:add` のテストでは `MISE_TASK_RUN_AUTO_INSTALL=false` を渡す。
`mise run` は既定で不足するツールを入れるので、これがないと `SKIP_TOOLS=1` でも全ツールを取得してしまう。
通常の `mise bootstrap --dry-run` は full 実行で、tools/task を省いた dry-run は `SKIP_TOOLS=1` で検証する。
clone が clean な状態の再実行に加え、`dot:add` 後にも bootstrap を実行する。

Worktrunk の連携設定は `/etc/xdg/worktrunk/config.toml` にコピーする。
`wt config update` が user config の symlink を維持したまま管理元を書き換えることを Docker で確認したため、
user config は管理しない。Herdr 0.9.1 の `worktree open` は symlink 経由でも metadata に実パスを保存する。
この実 CLI の挙動は、設定更新と symlink 経由の登録・削除のケースで確認する。

Worktrunk は `aqua:max-sixty/worktrunk` の `latest` を使う。registry の既定 backend は最新リリースしか返さず、
公開後 10 日の `install_before` を満たすバージョンが無くなるため。
最小 Docker イメージは `.config/mise/mise.toml` の宣言と `.config/mise/config.toml` の `install_before` を読み、
解決したバージョンを固定して入れる。どちらかを変更すると再構築される。
時間が経って新しいバージョンが解決できるようになったら `REBUILD=1` で取り直す。
base image の build と mise バージョンの検査は `tests/docker-helpers.sh` を両テストから共有する。

## mise のバージョン

- 必要な mise は **2026.9.8 以上**
  - 2026.9.1: bootstrap の hook で `{{config_root}}` が展開されず、bootstrap が失敗する
  - 2026.9.4〜9.7: bootstrap は通るが `mise dot` コマンドが無い (README の手順やテストで使う)
- テストのイメージはキャッシュされるので、mise は最初にビルドしたときのバージョンのまま使われる。新しい mise で試すには `REBUILD=1`、特定のバージョンで試すには `MISE_VERSION=v2026.9.8` を付ける
- ホストの mise はコンテナと別物。Docker で通っても、ホストで設定を読めるかは別に確かめる (作業ツリーで `MISE_TRUSTED_CONFIG_PATHS=$PWD mise config ls` など、書き込まないコマンドで)

## つまずいた点

- **グローバルの gitignore で新しいファイルが黙って除外される**: 古いグローバル ignore (`.*` や `*lefthook*`) が残っているマシンでは、`.miserc.toml` や `.config/` 配下の新しいファイルが `git add -A` で追加されない。コミット前に `git -c core.excludesFile=/dev/null status --short` と `git status --short` を見比べ、足りないものは `git add -f` する
- **テストのスナップショットは git に登録済み (stage 済みを含む) のファイルだけで作る**: CI が checkout するのと同じ内容で、無視されている秘密情報などをコンテナに渡さないため。新しいファイルはテストの前に `git add` (グローバル ignore に当たるなら `git add -f`、中身をまだ stage しないなら `git add -N`) する。登録を忘れたファイルはテストでも使われないので、コミット漏れに気づける
- **bootstrap の前にコンテナのホームにファイルを作らない**: `git config --global` で `~/.gitconfig` を作ると、dotfiles の配置と衝突する。git の設定は `GIT_CONFIG_COUNT` などの環境変数で渡す (テストスクリプト参照)
- **git の hook から呼ばれるスクリプトは `GIT_DIR` などを消してから git を使う**: git は hook の実行時に `GIT_DIR` などを設定する。これを引き継いだ `git init` が一時ディレクトリではなく呼び出し元のリポジトリを再初期化し、worktree から push したときに共有の設定へ `core.bare=true` が書かれて main の作業ツリーが使えなくなったことがある。`while IFS= read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)` で消す (tests/lefthook-dump.sh 参照)。直すときは `git -C <main のパス> config core.bare false`
- **リポジトリ内の `.config/mise/mise.toml` もプロジェクトの設定として読まれる**: clone しただけの状態では信頼されていないので、README の手順は `mise trust --all`。`--from` の後の hook ではパスを明示して trust する (`--from` の実行中は一時的に信頼されているので、`--all` は何も記録しない)
- **`--dry-run` は hook を実行しない**: 以前の手順の生成物が残った argc-completions は、除外を登録する pre-repos hook が動かないので `--dry-run` では「local changes」で止まる (実際の `mise bootstrap` は通る)
- **dotfiles のリンクをディレクトリ単位からファイル単位に変えるときは移行が要る**: 以前 `~/.config/git` をディレクトリごとリポジトリにリンクしていたマシンで `~/.config/git/ignore` をファイル単位でリンクすると、配置先がリポジトリのファイル自身になる。`--force-dotfiles` ではリポジトリの `ignore` が自分自身を指す symlink に置き換わり、中身が消えた。[bootstrap/migrate-dir-links.sh](../bootstrap/migrate-dir-links.sh) に対象を追加し、既存マシンのシナリオでテストする
- **`dotfiles.root` はチェックアウトの場所を表せない**: `{{config_root}}` は展開されず、その名前のディレクトリが作られる。相対パスは実行時のカレントディレクトリ基準で、リンクも相対パスで壊れる。固定のパスだと別のチェックアウト (worktree) から取り込んだときにファイルと設定が別々のチェックアウトに入る。設定の取り込みは `mise run dot:add <path>` を使う
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
