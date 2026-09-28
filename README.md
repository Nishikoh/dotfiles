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

- clone 先は `~/setup/dotfiles` にする。zsh の設定と `mise.toml` の `dotfiles.root` がこのパスを前提にしている
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
mise trust
mise bootstrap --dry-run
mise bootstrap
```

- 置き換え先に実ファイル (例: 以前コピーした `~/.config/lazygit`) があると dotfiles の配置で止まる。中身がリポジトリと同じか、取り込み済みであることを確かめてから `mise bootstrap --force-dotfiles` (WSL では `mise -E wsl bootstrap --force-dotfiles`) で置き換える
- codex: `~/.codex/config.toml` から [etc/codex/config.toml](etc/codex/config.toml) と重複するキーを取り除く。残すと `/etc/codex/config.toml` より優先される

## 日々の運用

```sh
cd ~/setup/dotfiles && git pull && mise bootstrap   # リポジトリの変更を反映する
mise upgrade                                       # ツールを更新する
mise bootstrap repos update                        # clone したリポジトリ (argc-completions など) を更新する
mise bootstrap status                              # 宣言どおりになっているか確認する
mise tasks                                         # 個別のタスク (setup:copilot など)
mise dot unapply                                   # dotfiles の symlink を外す

# 新しい設定を管理に加える (リポジトリで実行)。ファイルをリポジトリに移して symlink し、mise.toml に追記する
mise dot add -l ~/.config/foo
```

- `etc/codex/config.toml` はコピーなので、編集したら `mise bootstrap` で反映する
- symlink で配置したファイルは、`~/.config` 側で編集してもリポジトリに反映される

## test

開発時の手順とつまずいた点は [docs/development.md](docs/development.md) にまとめている。

```sh
# lefthook/*.yaml (lh で各リポジトリに取り込む設定) を検査する
lefthook run test

# Docker (Ubuntu, Arch) で mise bootstrap を試す。WSL は WSL_DISTRO_NAME で模擬する
bash tests/test-mise-bootstrap.sh
# 繰り返し試すときはツールのインストールを省いて GitHub API のレート制限を避ける
SKIP_TOOLS=1 bash tests/test-mise-bootstrap.sh

# bin/ssh のテスト
bash tests/test-ssh-wrapper.sh
```
