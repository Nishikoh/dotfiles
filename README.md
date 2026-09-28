# dotfiles

[![CI](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml/badge.svg?branch=master)](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml)

[mise bootstrap](https://mise.jdx.dev/bootstrap.html) でセットアップする。対象 OS は Ubuntu と Arch。

```sh
# 前提: curl, git, sudo
curl https://mise.run | sh
~/.local/bin/mise bootstrap --from https://github.com/Nishikoh/dotfiles.git --from-dir ~/setup/dotfiles --yes
# WSL では -E wsl を付ける (WSL 用の設定を mise.wsl.toml で差し替える)
~/.local/bin/mise -E wsl bootstrap --from https://github.com/Nishikoh/dotfiles.git --from-dir ~/setup/dotfiles --yes
```

clone 後は、リポジトリ内で実行すると [.miserc.toml](.miserc.toml) が `WSL_DISTRO_NAME` を見て wsl 環境を選ぶ。

clone 済みなら

```sh
cd ~/setup/dotfiles
mise trust
mise bootstrap --dry-run
mise bootstrap
```

- システムパッケージ / clone するリポジトリ / symlink する dotfiles: [mise.toml](mise.toml)
- インストールするツール: [.config/mise/](.config/mise/) (`~/.config/mise` にリンクされる)
- codex の設定: [etc/codex/config.toml](etc/codex/config.toml) (`/etc/codex/config.toml` にコピーされる。
  `~/.codex/config.toml` は codex が trust などを書き込む場所として残し、同じキーを書くとそちらが優先される)

```sh
mise bootstrap status   # 宣言どおりになっているか確認する
mise dot unapply        # dotfiles の symlink を外す
mise tasks              # 個別のセットアップタスク (setup:copilot など)

# 新しい設定を管理に加える (リポジトリで実行)。ファイルをリポジトリに移して symlink し、mise.toml に追記する
mise dot add -l ~/.config/foo
```

## test

```sh
lefthook run lint --all-files
lefthook run test

# Docker (Ubuntu, Arch) で mise bootstrap を試す
bash tests/test-mise-bootstrap.sh
# 繰り返し試すときはツールのインストールを省いて GitHub API のレート制限を避ける
SKIP_TOOLS=1 bash tests/test-mise-bootstrap.sh
```
