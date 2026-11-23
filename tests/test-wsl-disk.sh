#!/usr/bin/env bash
# bin/wsl-disk のテスト。スタブの powershell.exe・wslpath・df と偽の /sys/class/block で動かし、Windows にも実際のディスクにも触れない。
#
# 実行: bash tests/test-wsl-disk.sh   (リポジトリのどこからでも可。WSL でなくてよい)
set -uo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmd="$(cd "${test_dir}/.." && pwd)/bin/wsl-disk"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wsl-disk-test.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

stub_dir="${work_dir}/stub"
drive="${work_dir}/c" # C:\ に当たる場所
sys_block="${work_dir}/sys-block"
mkdir -p "${stub_dir}" "${drive}/wsl/ubuntu" "${drive}/Docker/main" "${sys_block}/sdd"

gib=$((1024 * 1024 * 1024))

# 中身の無いファイルは割り当てブロックが 0 なので、VHDX の容量はファイルの長さ (10GiB) になる
truncate -s $((10 * gib)) "${drive}/wsl/ubuntu/ext4.vhdx" "${drive}/Docker/main/ext4.vhdx"

# powershell.exe は registry.txt を CRLF で出す
cat >"${stub_dir}/powershell.exe" <<EOF
#!/usr/bin/env bash
sed 's/\$/\r/' "${work_dir}/registry.txt"
EOF

# wslpath -u 'C:\a\b' -> <drive>/a/b
cat >"${stub_dir}/wslpath" <<EOF
#!/usr/bin/env bash
[[ "\$1" == -u ]] || exit 1
p="\${2#C:}"
echo "${drive}\${p//\\\\//}"
EOF

# df は df-used.txt の used を使い、合計 9GiB の /dev/sdd を出す。df-used.txt が fail なら失敗する
cat >"${stub_dir}/df" <<EOF
#!/usr/bin/env bash
used=\$(cat "${work_dir}/df-used.txt")
[[ "\${used}" != fail ]] || exit 1
echo "Filesystem 1B-blocks Used Avail"
echo "/dev/sdd $((9 * gib)) \${used} 1"
EOF

# stat は stat-fail があれば失敗し (/mnt/c が読めないときに当たる)、無ければ本物を呼ぶ
cat >"${stub_dir}/stat" <<EOF
#!/usr/bin/env bash
[[ ! -e "${work_dir}/stat-fail" ]] || exit 1
exec "$(command -v stat)" "\$@"
EOF
chmod +x "${stub_dir}"/*

# ブロックデバイスは 10GiB なので、メタデータは 10GiB - 9GiB = 1GiB
echo $((10 * gib / 512)) >"${sys_block}/sdd/size"

write_registry() {
	printf '%s\n' \
		$'Ubuntu-24.04\tC:\\wsl\\ubuntu\text4.vhdx' \
		$'docker-desktop\t\\\\?\\C:\\Docker\\main\\' >"${work_dir}/registry.txt"
}
write_registry
echo $((6 * gib)) >"${work_dir}/df-used.txt"

failures=0
out=""
rc=0

run() {
	local distro="$1"
	shift
	out=$(PATH="${stub_dir}:${PATH}" WSL_DISTRO_NAME="${distro}" WSL_DISK_SYS_BLOCK="${sys_block}" "${cmd}" "$@" 2>&1)
	rc=$?
}

check() {
	local name="$1" want_rc="$2" want="$3"
	# bash の計算エラーは出力に混ざっても処理が続くことがあるので、出ていたら失敗にする
	if [[ "${rc}" -eq "${want_rc}" && "${out}" == *"${want}"* && "${out}" != *"syntax error"* ]]; then
		echo "ok   ${name}"
	else
		echo "FAIL ${name}: rc=${rc} (want ${want_rc}), want output containing: ${want}"
		printf '%s\n' "${out}" | sed 's/^/     | /'
		failures=$((failures + 1))
	fi
}

# 10GiB の VHDX、6GiB 使用、メタデータ 1GiB -> 減るのは 3〜4GiB
run Ubuntu-24.04
check "範囲で出す" 0 "compact で減る目安:   約 3.0GiB 〜 4.0GiB"
check "VHDX のパス" 0 'VHDX:                 C:\wsl\ubuntu\ext4.vhdx'
check "compact の手順" 0 "wsl --manage Ubuntu-24.04 --compact"
check "Optimize-VHD の手順" 0 "Optimize-VHD -Path 'C:\\wsl\\ubuntu\\ext4.vhdx' -Mode Full"
check "diskpart の手順" 0 'select vdisk file="C:\wsl\ubuntu\ext4.vhdx"'
[[ "${out}" != *$'\r'* ]] || {
	echo "FAIL CR が残っている"
	failures=$((failures + 1))
}

# \\?\ の接頭辞・末尾の \・空の VhdFileName (ext4.vhdx とみなす)
run docker-desktop
check "\\\\?\\ と空の VhdFileName" 0 'VHDX:                 C:\Docker\main\ext4.vhdx'

# デバイスの大きさが読めなければ最大だけ
rm "${sys_block}/sdd/size"
run Ubuntu-24.04
check "メタデータ不明なら最大だけ" 0 "compact で減る目安:   最大 4.0GiB"
echo $((10 * gib / 512)) >"${sys_block}/sdd/size"

# 使用量が VHDX より大きければ 0
echo $((11 * gib)) >"${work_dir}/df-used.txt"
run Ubuntu-24.04
check "負にならない" 0 "compact で減る目安:   最大 0.0B"
echo $((6 * gib)) >"${work_dir}/df-used.txt"

# デバイスの大きさが数字でなければ最大だけ
: >"${sys_block}/sdd/size"
run Ubuntu-24.04
check "メタデータが空なら最大だけ" 0 "compact で減る目安:   最大 4.0GiB"
echo $((10 * gib / 512)) >"${sys_block}/sdd/size"

touch "${work_dir}/stat-fail"
run Ubuntu-24.04
check "stat が失敗" 1 "の大きさを読めません"
rm "${work_dir}/stat-fail"

echo fail >"${work_dir}/df-used.txt"
run Ubuntu-24.04
check "df が失敗" 1 "df / で ext4 の使用量を読めません"

echo - >"${work_dir}/df-used.txt"
run Ubuntu-24.04
check "df の出力が数字でない" 1 "df の出力を解釈できません"
echo $((6 * gib)) >"${work_dir}/df-used.txt"

run Arch
check "レジストリに無い" 1 "レジストリに Arch が見つかりません"

run ""
check "WSL_DISTRO_NAME が空" 1 "WSL_DISTRO_NAME が空です"

run Ubuntu-24.04 --bogus
check "知らない引数" 2 "Usage: wsl-disk"

run Ubuntu-24.04 --help
check "--help" 0 "Usage: wsl-disk"

if ((failures > 0)); then
	echo "${failures} 件失敗"
	exit 1
fi
echo "すべて成功"
