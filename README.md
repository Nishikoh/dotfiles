# dotfiles

[![CI](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml/badge.svg?branch=master)](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml)

[mise bootstrap](https://mise.jdx.dev/bootstrap.html) でセットアップする。対象 OS は Ubuntu と Arch。

```sh
# 前提: curl, git, sudo
curl https://mise.run | sh
~/.local/bin/mise bootstrap --from https://github.com/Nishikoh/dotfiles.git --from-dir ~/setup/dotfiles --yes
```

clone 済みなら

```sh
cd ~/setup/dotfiles
mise trust
mise bootstrap --dry-run
mise bootstrap
```

- システムパッケージ / clone するリポジトリ / symlink する dotfiles: [mise.toml](mise.toml)
- インストールするツール: [.config/mise/](.config/mise/) (`~/.config/mise` にリンクされる)

```sh
mise bootstrap status   # 宣言どおりになっているか確認する
mise dot unapply        # dotfiles の symlink を外す
mise tasks              # 個別のセットアップタスク (setup:copilot など)
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
