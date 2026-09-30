#!/usr/bin/env bash
# トークンなしの最小検証。ツール取得は Docker build のキャッシュで再利用する。
# 実行: bash tests/test-worktrunk-herdr.sh [ubuntu] [arch] (引数なしなら両方)
# REBUILD=1: mise とツールを再取得する。MISE_VERSION: mise のバージョンを指定する。
set -euo pipefail
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$test_dir/.." && pwd)
source "$test_dir/docker-helpers.sh"
targets=("$@")
[[ ${#targets[@]} != 0 ]] || targets=(ubuntu arch)
image_suffix="${MISE_VERSION:+-${MISE_VERSION}}"
for target in "${targets[@]}"; do
	echo "===== Worktrunk / Herdr: $target ====="
	base_image="dotfiles-bootstrap:$target$image_suffix"
	image="dotfiles-worktrunk-herdr:$target$image_suffix"
	build_bootstrap_image "$target" "$repo_dir"
	# --pull はローカルで作った base image を Docker Hub から取得しようとするので、
	# ツールの layer には --no-cache だけを渡す。base image は上で --pull している。
	tool_args=()
	if [[ ${REBUILD:-} == 1 ]]; then tool_args+=(--no-cache); fi
	docker build -q "${tool_args[@]}" -f "$test_dir/Dockerfile.worktrunk-herdr" \
		--build-arg BASE_IMAGE="$base_image" -t "$image" "$repo_dir" >/dev/null
	docker run --rm \
		-v "$repo_dir/.config/worktrunk:/config:ro" \
		-v "$test_dir/worktrunk-herdr-cases.sh:/cases.sh:ro" \
		-v "$test_dir/docker-helpers.sh:/docker-helpers.sh:ro" \
		-e EXPECT_MISE_VERSION="${MISE_VERSION:-}" \
		"$image" bash -c '
			set -euo pipefail
			source /docker-helpers.sh
			check_mise_version
			sudo mkdir -p /etc/xdg/worktrunk
			sudo cp /config/config.toml /etc/xdg/worktrunk/config.toml
			mkdir -p ~/.config/worktrunk
			cp /config/herdr-hook.sh ~/.config/worktrunk/
			mise exec -- bash /cases.sh
		'
done
