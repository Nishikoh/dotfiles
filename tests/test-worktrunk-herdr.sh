#!/usr/bin/env bash
# トークンなしの最小検証。ツール取得は Docker build のキャッシュで再利用する。
# 実行: bash tests/test-worktrunk-herdr.sh [ubuntu] [arch] (引数なしなら両方)
set -euo pipefail
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$test_dir/.." && pwd)
targets=("$@")
[[ ${#targets[@]} != 0 ]] || targets=(ubuntu arch)
for target in "${targets[@]}"; do
	echo "===== Worktrunk / Herdr: $target ====="
	docker build -q --build-arg BASE="$target" -t "dotfiles-bootstrap:$target" "$repo_dir" >/dev/null
	docker build -q -f "$test_dir/Dockerfile.worktrunk-herdr" \
		--build-arg BASE_IMAGE="dotfiles-bootstrap:$target" -t "dotfiles-worktrunk-herdr:$target" "$repo_dir" >/dev/null
	docker run --rm \
		-v "$repo_dir/.config/worktrunk:/config:ro" \
		-v "$test_dir/worktrunk-herdr-cases.sh:/cases.sh:ro" \
		"dotfiles-worktrunk-herdr:$target" bash -c '
			set -euo pipefail
			mkdir -p ~/.config/worktrunk
			cp /config/* ~/.config/worktrunk/
			mise exec -- bash /cases.sh
		'
done
