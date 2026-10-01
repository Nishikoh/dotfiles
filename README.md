# dotfiles

[![CI](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml/badge.svg?branch=master)](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml)

[mise bootstrap](https://mise.jdx.dev/bootstrap.html) で Ubuntu と Arch (どちらも WSL を含む) をセットアップする。mise は 2026.9.8 以上が必要。

| 何を | どこで宣言しているか |
| --- | --- |
| OS パッケージ・clone するリポジトリ・symlink する dotfiles・タスク | [mise.toml](mise.toml) |
| WSL だけの差し替え | [mise.wsl.toml](mise.wsl.toml) ([.miserc.toml](.miserc.toml) が WSL のときに読み込む) |
| インストールするツール | [.config/mise/](.config/mise/) (`~/.config/mise` にリンクされる) |
| codex の設定 | [etc/codex/config.toml](etc/codex/config.toml) (`/etc/codex/config.toml` にコピーされる) |

## 新しいマシン

### 1. 前提をそろえる

```sh
# Ubuntu
sudo apt-get update && sudo apt-get install -y ca-certificates curl git
# Arch
sudo pacman -S --needed curl git sudo

# mise (~/.local/bin/mise に入る。zsh の設定 zsh/02path.zsh はこのパスの mise を使う)
curl https://mise.run | sh
```

### 2. bootstrap する

```sh
# Ubuntu / Arch
~/.local/bin/mise bootstrap --from https://github.com/Nishikoh/dotfiles.git --from-dir ~/setup/dotfiles --yes

# WSL では -E wsl を付ける
~/.local/bin/mise -E wsl bootstrap --from https://github.com/Nishikoh/dotfiles.git --from-dir ~/setup/dotfiles --yes
```

- clone 先は `~/setup/dotfiles` にする。zsh の設定がこのパスを前提にしている
- OS パッケージと `/etc/codex` を入れるときに sudo のパスワードを聞かれる (`--yes` が省くのは mise の確認だけ)
- ツールのインストールで GitHub API のレート制限に当たったら、`GITHUB_TOKEN` を設定して再実行する

### 3. 実行後にやること

```sh
# ログインシェルを zsh にする (bootstrap は変更しない)。反映はログインし直してから
sudo chsh -s /usr/bin/zsh "$(id -un)"
```

- 必要なら対話的なセットアップをする: `mise run setup:copilot` (GitHub へのログイン)、claude や codex などは初回起動時にログインする
- WSL では [.config/herdr/config.wsl.toml](.config/herdr/config.wsl.toml) を WSL 用 (ssh・画面描画・通知) に調整してコミットする。今は WSL 以外の設定のコピー

## WSL

- リポジトリ内で mise を実行すると、[.miserc.toml](.miserc.toml) が `WSL_DISTRO_NAME` を見て `wsl` 環境を選び、[mise.wsl.toml](mise.wsl.toml) が herdr の設定を `config.wsl.toml` に差し替える
- `WSL_DISTRO_NAME` が無い実行 (ssh 経由など) や、初回に `-E wsl` を付け忘れた場合は、次のメッセージで止まる。`mise -E wsl bootstrap` で再実行する

  ```text
  WSL ですが WSL 用の設定がリンクされていません。'mise -E wsl bootstrap' で再実行してください
  ```

- [bin/ssh](bin/ssh) は WSL では Windows の `ssh.exe` を使う (仕組みはファイル冒頭のコメント)

## 既存のマシンに適用する

前提: `~/setup/dotfiles` に clone してあり、2026.9.8 以上の mise が `~/.local/bin/mise` にある (`curl https://mise.run | sh` で入る。パッケージマネージャーで入れた mise だけだと、zsh の起動時に `~/.local/bin/mise` が見つからずエラーになる。`mise --version` で確認し、古ければ `mise self-update`)。

```sh
cd ~/setup/dotfiles
git pull
mise trust --all   # リポジトリ内の .config/mise/mise.toml も一緒に信頼する
mise bootstrap --dry-run
mise bootstrap
```

- 置き換え先に実ファイル (例: 以前コピーした `~/.config/lazygit`) があると dotfiles の配置で止まる。中身がリポジトリと同じか、取り込み済みであることを確かめてから `mise bootstrap --force-dotfiles` (WSL では `mise -E wsl bootstrap --force-dotfiles`) で置き換える
- 以前の手順で `~/.config/git` をディレクトリごとリポジトリにリンクしていたマシンでは、bootstrap がリンクを外して実ディレクトリに戻す (他のツールがリポジトリ側に書いた `config` などはそこへ移す)。`--dry-run` は hook を実行しないので、このようなマシンでは `~/.config/git/ignore` の衝突を報告して止まる
- 以前の手順 (Argcfile.sh) で補完を生成したマシンでは、`~/setup/argc-completions` に残った生成物のせいで `--dry-run` が「local changes」で止まる。`mise bootstrap` は repos フェーズの前に生成物を git から無視させるので、そのまま実行してよい
- codex: `~/.codex/config.toml` から [etc/codex/config.toml](etc/codex/config.toml) と重複するキーを取り除く。残すと `/etc/codex/config.toml` より優先される

## 日々の運用

```sh
cd ~/setup/dotfiles && git pull && mise bootstrap   # リポジトリの変更を反映する
mise upgrade                                       # ツールを更新する
mise bootstrap repos update                        # clone したリポジトリ (argc-completions など) を更新する
mise bootstrap status                              # 宣言どおりになっているか確認する
mise tasks                                         # 個別のタスク (setup:copilot など)
mise dot unapply                                   # dotfiles の symlink を外す

# 新しい設定を管理に加える (チェックアウトの中で実行)。ファイルをそのチェックアウトに移して symlink し、mise.toml に相対パスで追記する
mise run dot:add ~/.config/foo
```

- `etc/codex/config.toml` はコピーなので、編集したら `mise bootstrap` で反映する
- symlink で配置したファイルは、`~/.config` 側で編集してもリポジトリに反映される

## Worktrunk と Herdr

[.config/worktrunk/config.toml](.config/worktrunk/config.toml) は mise bootstrap で
読み込み専用の `/etc/xdg/worktrunk/config.toml` (System 設定) にコピーする。
[herdr-hook.sh](.config/worktrunk/herdr-hook.sh) と [herdr-shell.sh](.config/worktrunk/herdr-shell.sh) は mise dot でファイル単位でリンクする。
設定を変更したら `mise bootstrap` でコピーを更新する。
Worktrunk が自動更新する `~/.config/worktrunk/config.toml` と `approvals.toml` はマシン固有のまま保持する。

Herdr の worktree と同じく、1 つの worktree を 1 つの workspace に対応させ、リポジトリの workspace の下に並べる。
Herdr を起動しておけば、普段どおり `wt` を使うだけでよい。

```text
サイドバー
  repo            ← primary (main) の workspace
    ├ feature/auth ← feature/auth の checkout はこの workspace だけにある
    └ fix-login
```

```sh
wt switch --create feature/auth   # feature/auth の workspace を作って移動する。操作した pane は cd しない
wt switch main                    # repo の workspace に戻る。feature/auth の pane はそのまま
wt merge                          # feature/auth の workspace を閉じ、repo の workspace に戻る
```

- Herdr の pane の中では、`wt` の cd を移動先の worktree の workspace への focus に置き換える
  ([herdr-shell.sh](.config/worktrunk/herdr-shell.sh) を zsh で読み込む)。
  `switch` / `switch -` / `switch ^` / picker / `merge` / `remove` のどれでも同じ。
  操作元と同じ workspace 内の移動、Herdr の外、bare リポジトリ、focus に失敗した場合は通常どおり cd する
- `--no-cd` を付けると、focus は移動せずに workspace をサイドバーに追加するだけになる
- `-x` (`--execute`) のプログラムは操作した pane で動く。worktree の workspace で動かす場合は、そこで起動する
- repo の workspace が無ければ focus を奪わずに作る。Herdr のサーバーは自動で起動しない
- 削除 (`wt remove` / `wt merge` / 通常の background 削除 / 現在の checkout の削除) が成功したら、
  その workspace で待機中の shell の pane を閉じる。最後の pane を閉じると workspace も閉じ、見ていた場合は repo の workspace に戻る。
  dirty checkout や他の hook による削除拒否では閉じない
- 何かを実行中の pane (エージェント、エディタ、`&` で動かした dev server などの background job) は削除後も残す。
  Herdr は pane を閉じると中のプロセスをすべて終了させるため。終わったら Herdr 側で閉じる。
  `wt` を実行した pane は、Worktrunk の background 削除と他の hook が終わるまで (最大 60 秒) 待ってから閉じる
- 両 hook は background で動く。リポジトリごとの lock と checkout の再確認で、遅延した登録と削除、同じパスでの再作成に対応する。
  lock が空くまで待つため、複数削除でキューが長くなってもイベントを落とさない
- 同じパスの再作成は、shell の cwd が保持する directory と現在の checkout root を比較して判定する。
  古い checkout に残った pane は置き換え、同じ checkout 内で子ディレクトリを消しただけなら閉じない。
  別の場所の pane だけが残った workspace が再利用された場合は、現在の checkout 用 pane を一度だけ追加する
- `--no-hooks` や `git worktree` で直接削除した場合、`wt step relocate` の後に switch せずに削除した場合の workspace は、
  次に同じリポジトリで `wt switch` / `wt remove` したときに片付ける。relocate した checkout は次の `wt switch` で同じ workspace を引き継ぐ
- CLI / jq が無い、応答が止まった場合も時間制限で終え、Herdr の同期失敗で `wt` の操作を止めない。
  API への同期失敗時に自動再試行はしない。cwd を確認できない pane は閉じない
- `HERDR_SESSION` / `HERDR_SOCKET_PATH` を引き継ぎ、そのサーバーだけに同期する。bare リポジトリは Herdr の worktree API が扱えないのでスキップする
- Herdr 再起動後の既存 checkout は `wt switch` で再選択すれば登録できる
- hook スクリプトの配置先は `$HOME/.config/worktrunk/herdr-hook.sh`。`XDG_CONFIG_HOME` を変更してもここから実行し、無いユーザー (sudo の root など) ではスキップする

hook の確認は `wt hook show`、登録の再実行は対象 checkout で `wt hook post-switch herdr-open --foreground`。
hook の仕様は [Worktrunk](https://worktrunk.dev/hook/)、workspace の Git 情報は
[Herdr の API schema](https://github.com/herdrdev/herdr/blob/master/src/api/schema/workspaces.rs) を参照。

## test

開発時の手順とつまずいた点は [docs/development.md](docs/development.md) にまとめている。

```sh
# lefthook/*.yaml (lh で各リポジトリに取り込む設定) を検査する
lefthook run test

# Docker (Ubuntu, Arch) で mise bootstrap を試す。WSL は WSL_DISTRO_NAME で模擬する
bash tests/test-mise-bootstrap.sh
# 繰り返し試すときはツールのインストールを省いて GitHub API のレート制限を避ける
SKIP_TOOLS=1 bash tests/test-mise-bootstrap.sh
# ツールまで含めるときは GITHUB_TOKEN を明示して渡す (認証なしは 60 回/時で足りない。権限なしのトークンで十分)
GITHUB_TOKEN=... bash tests/test-mise-bootstrap.sh

# bin/ssh のテスト
bash tests/test-ssh-wrapper.sh

# トークンなしで実際の Worktrunk / Herdr の連携だけを Docker (Ubuntu / Arch) で検証する
# ツールは worktrunk・herdr・jq のみ。ビルド済みイメージを再利用する
bash tests/test-worktrunk-herdr.sh
# キャッシュ内の mise / ツールを取り直す。mise のバージョンを指定することもできる
REBUILD=1 MISE_VERSION=v2026.9.17 bash tests/test-worktrunk-herdr.sh ubuntu
```
