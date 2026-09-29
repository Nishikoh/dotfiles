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
mise trust --all   # リポジトリ内の .config/mise/mise.toml も一緒に信頼する
mise bootstrap --dry-run
mise bootstrap
```

以前の手順 (Argcfile.sh) で補完を生成したマシンでは、`~/setup/argc-completions` に残った生成物のせいで `--dry-run` が「local changes」で止まる。`mise bootstrap` は repos フェーズの前に生成物を git から無視させるので、そのまま実行してよい。

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
# ツールまで含めるときは GITHUB_TOKEN を明示して渡す (認証なしは 60 回/時で足りない。権限なしのトークンで十分)
GITHUB_TOKEN=... bash tests/test-mise-bootstrap.sh
```
