#!/usr/bin/env bash
# host と container から source する、bootstrap テスト共通の関数。
bootstrap_image_tag() {
	echo "dotfiles-bootstrap:$1${MISE_VERSION:+-$MISE_VERSION}"
}

# tag は bootstrap_image_tag で取得する。コマンド置換の中では set -e が効かず、
# build の失敗を見逃すので、この関数は通常のコマンドとして呼ぶ。
build_bootstrap_image() {
	local target=$1 repo_dir=$2
	local -a build_args=()
	if [[ -n ${MISE_VERSION:-} ]]; then build_args+=(--build-arg "MISE_VERSION=$MISE_VERSION"); fi
	if [[ ${REBUILD:-} == 1 ]]; then build_args+=(--pull --no-cache); fi
	docker build -q "${build_args[@]}" --build-arg "BASE=$target" \
		-t "$(bootstrap_image_tag "$target")" "$repo_dir" >/dev/null
}

check_mise_version() {
	local actual
	actual=$(mise --version)
	echo "::: mise $actual"
	if [[ -n ${EXPECT_MISE_VERSION:-} && "$actual" != "${EXPECT_MISE_VERSION#v} "* ]]; then
		echo "NG: MISE_VERSION=$EXPECT_MISE_VERSION を指定したが、入っているのは $actual" >&2
		return 1
	fi
}
