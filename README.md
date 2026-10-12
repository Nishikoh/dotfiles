# dotfiles

[![CI](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml/badge.svg?branch=master)](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml)

[mise bootstrap](https://mise.jdx.dev/bootstrap.html) で Ubuntu と Arch (どちらも WSL を含む) をセットアップする。mise は 2026.9.8 以上が必要。

| 何を | どこで宣言しているか |
| --- | --- |
| OS パッケージ・clone するリポジトリ・symlink する dotfiles・タスク | [mise.toml](mise.toml) |
| WSL だけの差し替え | [mise.wsl.toml](mise.wsl.toml) ([.miserc.toml](.miserc.toml) が WSL のときに読み込む) |
| インストールするツール | [.config/mise/](.config/mise/) (`~/.config/mise` にリンクされる)。既定で外すツール (プリセット) は `config.toml` の `disable_tools`、マシンごとの変更は `~/.config/mise/config.local.toml` ([マシンごとにツールを外す](#マシンごとにツールを外す)) |
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
- 使うツールが少ないマシンは、先に [最小構成のマシン](#最小構成のマシン) を読む

### 3. 実行後にやること

```sh
# ログインシェルを zsh にする (bootstrap は変更しない)。反映はログインし直してから
sudo chsh -s /usr/bin/zsh "$(id -un)"
```

- 必要なら対話的なセットアップをする: `mise run setup:copilot` (GitHub へのログイン)、claude や codex などは初回起動時にログインする
- gcloud など一部のツールは既定で入らない (bootstrap の最後に `外しているツール: ...` と表示される)。使うものは `mise run tools:enable` で入れる ([マシンごとにツールを外す](#マシンごとにツールを外す))
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

## マシンごとにツールを外す

外したツールは bootstrap や `mise upgrade` でインストールされず、PATH にも出ない。既定では [.config/mise/config.toml](.config/mise/config.toml) の `disable_tools` (プリセット。大きいツールや、使わないマシンが多いツール) を外す。新しいマシンもプリセットのまま bootstrap し、必要ならあとから変える。

```sh
# チェックアウトの中で実行する
mise run tools:status                  # 外しているツールと、その設定元 (プリセットかこのマシンか) を表示する
mise run tools:enable gcloud           # 戻してインストールする
mise run tools:disable duckdb rclone   # 外してアンインストールする (ディスクと shim も消える)
mise run tools:disable                 # 引数を省くと fzf で選ぶ (TAB で選択、ENTER で決定)。tools:enable も同じ
```

- 変更は `~/.config/mise/config.local.toml` の `disable_tools` に書かれる。プリセットと同じに戻ると消え、以後はプリセットの変更に従う。`~/.config/mise` はリポジトリへの symlink なので実体はリポジトリの `.config/mise/` にあるが、git では無視される
- 手で編集するときの注意 (タスクはこれらを扱う):
  - `disable_tools` はプリセットに足されず**置き換わる**。そのマシンで外すツールをすべて書く (`[]` ならすべて入れる)
  - 名前は [.config/mise/mise.toml](.config/mise/mise.toml) のキーと同じにする (例: `"github:tofuutils/tenv"`)。違う名前は何も言わずに無視される
  - 外しただけではインストール済みのものが残り、shim を実行すると `not a valid shim` のエラーになる。`mise uninstall --all <tool>` で消す (`mise prune` では消えない)
- 外したツールは、プロジェクトの `mise.toml` に書かれていても使われない。rust などを使うプロジェクトがあるマシンでは `mise run tools:enable rust` で戻す
- bun・uv・lefthook・fzf は外さない (npm: と pipx: のツール、git の hook、zsh の設定と tools タスクの選択で使う)。`tools:disable` も外さない
- リポジトリの別のチェックアウト (worktree) の中では、そのチェックアウトの `.config/mise/config.toml` が優先されるので、このマシンの設定に関係なくプリセットになる (`tools:status` は食い違うときに表示する)

## 最小構成のマシン

使うツールが少ないマシンでは、外すものを並べるより、使うものを並べる。`~/.config/mise/config.local.toml` の `enable_tools` (許可リスト) に書いたツールだけを入れ、それ以外は入らない。プリセットの `disable_tools` は使われない。

1. 初回の bootstrap は、環境変数で許可リストを渡す (`minimal` と同じ一覧)。`~/.config/mise` はまだ無いので、ファイルは書けない。全部入れてから外すと時間とディスクを使う

   ```sh
   MISE_ENABLE_TOOLS=argc,bat,bun,claude,codex,eza,fzf,helix,herdr,node,starship,uv ~/.local/bin/mise bootstrap --from https://github.com/Nishikoh/dotfiles.git --from-dir ~/setup/dotfiles --yes
   ```

2. 終わったら、プリセットを選ぶ。以後の `mise install` と `mise upgrade` はこの一覧に従う

   ```sh
   mise run tools:preset minimal   # 一覧を ~/.config/mise/config.local.toml に書く
   ```

   プリセットは [.config/mise/presets/](.config/mise/presets/) にある。今の `minimal` は argc・bat・bun・claude・codex・eza・fzf・helix・herdr・node・starship・uv。ほかの一覧が要るときは、プリセットのファイルを足す。`mise run tools:preset off` で元の (外すツールを決める) 形に戻す

- 一覧には使うツールだけを書く。`argc` は `mise run bootstrap` が補完を生成するのに使う。`bun`・`uv`・`lefthook`・`fzf` は、npm: と pipx: のツール、git の hook、tools の選択で使うなら入れる
- 一覧は置き換わる (プリセットに足されない)。一覧に無いツールは、プロジェクトの `mise.toml` に書いてあっても使われない
- 名前を間違えても何も言われない。`mise ls` で入っているものを確かめる
- 許可リストのマシンでは `tools:disable` と `tools:enable` は使えない。一覧を変えるのは `tools:preset` (または `config.local.toml` の `enable_tools` を手で編集する)。`mise run tools:status` で確かめる
- 既存のマシンで後から一覧を書いた場合、一覧から外れたツールは残り、shim を実行すると `not a valid shim` のエラーになる。`mise uninstall --all <tool>` で消す (shim も消える)

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
```
