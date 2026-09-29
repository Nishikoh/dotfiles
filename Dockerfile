# mise bootstrap の動作確認用イメージ (tests/test-mise-bootstrap.sh から使う)
#   docker build --build-arg BASE=ubuntu -t dotfiles-bootstrap:ubuntu .
#   docker build --build-arg BASE=arch -t dotfiles-bootstrap:arch .
#
# 新しいマシンを想定し、mise bootstrap の前提 (curl, git, sudo) と mise だけを入れておく。
# Ubuntu はパッケージリストをあえて消しておき、mise が apt-get update することを確認する。
# Arch は同期 DB が無いと mise の pacman -Q が失敗するため残す (実機の Arch には必ずある)。
ARG BASE=ubuntu

# 新しいマシンの再現なので、あえて最新のイメージとパッケージを使う
# hadolint ignore=DL3007
FROM mirror.gcr.io/ubuntu:latest AS ubuntu-base
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl git sudo && \
    rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3007
FROM mirror.gcr.io/archlinux:latest AS arch-base
RUN pacman -Syu --noconfirm --needed curl git sudo && \
    rm -rf /var/cache/pacman/pkg/*

FROM ${BASE}-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# sudo をパスワードなしで使える一般ユーザーで検証する
RUN useradd -m -s /bin/bash dev && echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev
USER dev
WORKDIR /home/dev
ENV PATH=/home/dev/.local/bin:$PATH
ARG MISE_VERSION
RUN curl -fsSL https://mise.run | sh && mise --version
