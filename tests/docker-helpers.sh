#!/usr/bin/env bash
# host と container から source する、bootstrap テスト共通の関数。
bootstrap_image_tag() {
	echo "dotfiles-bootstrap:$1${MISE_VERSION:+-$MISE_VERSION}"
}

# build した image の tag を出力する。
build_bootstrap_image() {
	local target=$1 repo_dir=$2 tag
	local -a build_args=()
	tag=$(bootstrap_image_tag "$target")
	if [[ -n ${MISE_VERSION:-} ]]; then build_args+=(--build-arg "MISE_VERSION=$MISE_VERSION"); fi
	if [[ ${REBUILD:-} == 1 ]]; then build_args+=(--pull --no-cache); fi
	docker build -q "${build_args[@]}" --build-arg "BASE=$target" -t "$tag" "$repo_dir" >/dev/null
	echo "$tag"
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
