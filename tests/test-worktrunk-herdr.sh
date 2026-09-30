#!/usr/bin/env bash
# トークンなしの最小検証。ツール取得は Docker build のキャッシュで再利用する。
# 実行: bash tests/test-worktrunk-herdr.sh [ubuntu] [arch] (引数なしなら両方)
# REBUILD=1: mise とツールを再取得する。MISE_VERSION: mise のバージョンを指定する。
set -euo pipefail
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$test_dir/.." && pwd)
targets=("$@")
[[ ${#targets[@]} != 0 ]] || targets=(ubuntu arch)
image_suffix="${MISE_VERSION:+-${MISE_VERSION}}"
base_args=()
refresh_args=()
if [[ -n ${MISE_VERSION:-} ]]; then base_args+=(--build-arg "MISE_VERSION=$MISE_VERSION"); fi
if [[ ${REBUILD:-} == 1 ]]; then refresh_args+=(--pull --no-cache); fi
for target in "${targets[@]}"; do
	echo "===== Worktrunk / Herdr: $target ====="
	base_image="dotfiles-bootstrap:$target$image_suffix"
	image="dotfiles-worktrunk-herdr:$target$image_suffix"
	docker build -q "${refresh_args[@]}" "${base_args[@]}" --build-arg BASE="$target" -t "$base_image" "$repo_dir" >/dev/null
	# --pull はローカルで作った base image を Docker Hub から取得しようとするので、
	# ツールの layer には --no-cache だけを渡す。base image は上で --pull している。
	tool_args=()
	if [[ ${REBUILD:-} == 1 ]]; then tool_args+=(--no-cache); fi
	docker build -q "${tool_args[@]}" -f "$test_dir/Dockerfile.worktrunk-herdr" \
		--build-arg BASE_IMAGE="$base_image" -t "$image" "$repo_dir" >/dev/null
	docker run --rm \
		-v "$repo_dir/.config/worktrunk:/config:ro" \
		-v "$test_dir/worktrunk-herdr-cases.sh:/cases.sh:ro" \
		-e EXPECT_MISE_VERSION="${MISE_VERSION:-}" \
		"$image" bash -c '
			set -euo pipefail
			echo "::: mise $(mise --version)"
			if [[ -n "$EXPECT_MISE_VERSION" ]]; then
				mise --version | grep -q "^${EXPECT_MISE_VERSION#v} "
			fi
			sudo mkdir -p /etc/xdg/worktrunk
			sudo cp /config/config.toml /etc/xdg/worktrunk/config.toml
			mkdir -p ~/.config/worktrunk
			cp /config/herdr-hook.sh ~/.config/worktrunk/
			mise exec -- bash /cases.sh
		'
done
