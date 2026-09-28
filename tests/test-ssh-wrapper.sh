#!/usr/bin/env bash
# bin/ssh のテスト。偽の binfmt_misc・スタブの ssh.exe と ssh・隔離した PATH で動かし、ネットワークには出ない。
#
# 実行: bash tests/test-ssh-wrapper.sh   （リポジトリのどこからでも可）
#
# 判定の考え方:
#   - 「Windows 側が呼ばれる」ケースと「Linux 側が呼ばれる」ケースを同じスタブで対にし、検出器の生存を担保する。
#   - PATH には実際の ssh を含めない（bash と cat だけを置いた tools/ を使う）。実機の ssh に依存せずに再帰と不在を試す。
#   - 最後の実機ケースだけは本物の ssh.exe を -V で起動する。WSL interop が無い環境では SKIP する。
#   - 各実行は GNU timeout（無ければ gtimeout）で 10 秒に制限する。どちらも無い macOS では制限なしで動かす。
set -uo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${test_dir}/.." && pwd)"
wrapper="${repo_dir}/bin/ssh"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/ssh-wrapper-test.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

tools_dir="${work_dir}/tools"         # スタブとラッパーの shebang（env bash）と、スタブの cat だけを置く
linux_dir="${work_dir}/linux"         # 本来の ssh のスタブ
wsl_binfmt="${work_dir}/binfmt-wsl"   # WSLInterop が登録された binfmt_misc
late_binfmt="${work_dir}/binfmt-late" # WSLInterop-late だけが登録された binfmt_misc
plain_binfmt="${work_dir}/binfmt-none"
link_dir="${work_dir}/link" # ラッパーへの symlink（~/.local/bin/ssh -> dotfiles/bin/ssh のような配置）
wrapper_dir="$(dirname "${wrapper}")"

# Windows のドライブを模した配置。ssh.exe のパスは実物と同じく <drive>/Windows/System32/OpenSSH/ssh.exe。
openssh_path="Windows/System32/OpenSSH/ssh.exe"
windows_ssh_stub="${work_dir}/drive/${openssh_path}"                   # OpenSSH が入った Windows
noexec_windows_ssh="${work_dir}/drive-noexec/${openssh_path}"          # ssh.exe はあるが実行権限が無い
missing_openssh_ssh="${work_dir}/drive-without-openssh/${openssh_path}" # System32 はあるが OpenSSH が無い
no_drive_ssh="${work_dir}/no-drive/${openssh_path}"                    # Windows のドライブが無い（コンテナなど）

mkdir -p "${tools_dir}" "${linux_dir}" "${wsl_binfmt}" "${late_binfmt}" "${plain_binfmt}" "${link_dir}" \
  "$(dirname "${windows_ssh_stub}")" "$(dirname "${noexec_windows_ssh}")" \
  "$(dirname "$(dirname "${missing_openssh_ssh}")")"
ln -s "$(command -v bash)" "${tools_dir}/bash"
ln -s "$(command -v cat)" "${tools_dir}/cat"
touch "${wsl_binfmt}/WSLInterop" "${late_binfmt}/WSLInterop-late" "${plain_binfmt}/register"
ln -s "${wrapper}" "${link_dir}/ssh"

timeout_bin="$(command -v timeout || command -v gtimeout || true)"
run_limited() {
  if [[ -n "${timeout_bin}" ]]; then "${timeout_bin}" 10s "$@"; else "$@"; fi
}

export STUB_RECORD="${work_dir}/record"
export STUB_STDIN="${work_dir}/stdin-received"
export STUB_EXIT=0

# スタブは呼ばれた側の名前・SSH_AUTH_SOCK・引数（1 行 1 引数）を記録し、STUB_STDIN があれば stdin を写す。
make_stub() {
  local name="$1" path="$2"
  cat >"${path}" <<STUB
#!/usr/bin/env bash
{
  printf 'name=%s\n' '${name}'
  printf 'auth_sock=%s\n' "\${SSH_AUTH_SOCK-<unset>}"
  printf 'argc=%d\n' "\$#"
  for arg in "\$@"; do printf 'arg=%s\n' "\${arg}"; done
} >"\${STUB_RECORD}"
if [[ -n "\${STUB_COPY_STDIN:-}" ]]; then cat >"\${STUB_STDIN}"; fi
exit "\${STUB_EXIT}"
STUB
  chmod +x "${path}"
}
make_stub linux "${linux_dir}/ssh"
make_stub windows "${windows_ssh_stub}"
make_stub windows "${noexec_windows_ssh}"
chmod -x "${noexec_windows_ssh}"

pass_count=0
fail_count=0
skip_count=0

pass() { pass_count=$((pass_count + 1)); printf 'PASS  %s\n' "$1"; }
fail() { fail_count=$((fail_count + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }
skip() { skip_count=$((skip_count + 1)); printf 'SKIP  %s（%s）\n' "$1" "$2"; }

recorded() { grep -qxF -- "$1" "${STUB_RECORD}" 2>/dev/null; }
recorded_name() { sed -n 's/^name=//p' "${STUB_RECORD}" 2>/dev/null; }

# ラッパーを 1 回実行し、rc と stderr_out を設定する。stdin は /dev/null、stdout は捨てる。
# 引数: path_value, binfmt_dir, windows_ssh, ラッパーへの引数...
rc=0
stderr_out=""
run_wrapper() {
  local path_value="$1" binfmt="$2" windows_ssh="$3"
  shift 3
  rm -f "${STUB_RECORD}" "${STUB_STDIN}"
  stderr_out="$(run_limited env SSH_WRAPPER_BINFMT_DIR="${binfmt}" SSH_WRAPPER_WINDOWS_SSH="${windows_ssh}" \
    PATH="${path_value}" "${wrapper}" "$@" </dev/null 2>&1 >/dev/null)"
  rc=$?
}

standard_path="${wrapper_dir}:${linux_dir}:${tools_dir}"
# '$HOME *' は展開されない文字列のまま渡ることを確かめるための値なので、単一引用符が意図どおり。
# shellcheck disable=SC2016
tricky_args=(-T 'dev host' '' 'uname -s; uname -m' '--' "it's \"quoted\"" '$HOME *')

echo "== 判定と振り分け =="
export SSH_AUTH_SOCK=/tmp/linux-agent.sock

run_wrapper "${standard_path}" "${wsl_binfmt}" "${windows_ssh_stub}" "${tricky_args[@]}"
if [[ "${rc}" -eq 0 && "$(recorded_name)" == windows ]]; then
  pass "WSLInterop があり ssh.exe を実行できる → ssh.exe"
else
  fail "WSLInterop があり ssh.exe を実行できる → ssh.exe" "rc=${rc} name=$(recorded_name) stderr=${stderr_out}"
fi
if recorded 'auth_sock=<unset>'; then
  pass "ssh.exe には SSH_AUTH_SOCK を渡さない"
else
  fail "ssh.exe には SSH_AUTH_SOCK を渡さない" "$(grep '^auth_sock=' "${STUB_RECORD}" 2>/dev/null)"
fi
expected_args="${work_dir}/expected-args"
{
  printf 'argc=%d\n' "${#tricky_args[@]}"
  for arg in "${tricky_args[@]}"; do printf 'arg=%s\n' "${arg}"; done
} >"${expected_args}"
if diff -u "${expected_args}" <(grep -E '^(argc|arg)=' "${STUB_RECORD}") >/dev/null; then
  pass "空白・空文字・引用符・glob を含む引数をそのまま ssh.exe へ渡す"
else
  fail "空白・空文字・引用符・glob を含む引数をそのまま ssh.exe へ渡す" "$(diff -u "${expected_args}" <(grep -E '^(argc|arg)=' "${STUB_RECORD}"))"
fi
if [[ -z "${stderr_out}" ]]; then pass "ssh.exe 経路では stderr に何も書かない"; else fail "ssh.exe 経路では stderr に何も書かない" "${stderr_out}"; fi

run_wrapper "${standard_path}" "${late_binfmt}" "${windows_ssh_stub}" -V
if [[ "${rc}" -eq 0 && "$(recorded_name)" == windows ]]; then
  pass "WSLInterop-late だけでも WSL と判定する"
else
  fail "WSLInterop-late だけでも WSL と判定する" "rc=${rc} name=$(recorded_name)"
fi

run_wrapper "${standard_path}" "${plain_binfmt}" "${windows_ssh_stub}" "${tricky_args[@]}"
if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux ]]; then
  pass "WSLInterop が無い（WSL 以外・interop 無効）→ ssh.exe があっても本来の ssh"
else
  fail "WSLInterop が無い（WSL 以外・interop 無効）→ ssh.exe があっても本来の ssh" "rc=${rc} name=$(recorded_name) stderr=${stderr_out}"
fi
if recorded "auth_sock=${SSH_AUTH_SOCK}"; then
  pass "本来の ssh には SSH_AUTH_SOCK をそのまま渡す"
else
  fail "本来の ssh には SSH_AUTH_SOCK をそのまま渡す" "$(grep '^auth_sock=' "${STUB_RECORD}" 2>/dev/null)"
fi
if diff -u "${expected_args}" <(grep -E '^(argc|arg)=' "${STUB_RECORD}") >/dev/null; then
  pass "本来の ssh へも引数をそのまま渡す"
else
  fail "本来の ssh へも引数をそのまま渡す" "$(diff -u "${expected_args}" <(grep -E '^(argc|arg)=' "${STUB_RECORD}"))"
fi
if [[ -z "${stderr_out}" ]]; then pass "WSL 以外では stderr に何も書かない"; else fail "WSL 以外では stderr に何も書かない" "${stderr_out}"; fi

echo "== WSL で ssh.exe を使えないとき =="
run_wrapper "${standard_path}" "${wsl_binfmt}" "${missing_openssh_ssh}" -V
if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux && "${stderr_out}" == *"${missing_openssh_ssh} を実行できない"* ]]; then
  pass "Windows はあるが OpenSSH が無い → 本来の ssh を使い、stderr で知らせる"
else
  fail "Windows はあるが OpenSSH が無い → 本来の ssh を使い、stderr で知らせる" "rc=${rc} name=$(recorded_name) stderr=${stderr_out}"
fi

run_wrapper "${standard_path}" "${wsl_binfmt}" "${noexec_windows_ssh}" -V
if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux && "${stderr_out}" == *"${noexec_windows_ssh} を実行できない"* ]]; then
  pass "ssh.exe に実行権限が無い → 本来の ssh を使い、stderr で知らせる"
else
  fail "ssh.exe に実行権限が無い → 本来の ssh を使い、stderr で知らせる" "rc=${rc} name=$(recorded_name) stderr=${stderr_out}"
fi

# WSL 上の特権コンテナが binfmt_misc を mount すると WSLInterop が見えるが、Windows のドライブは無い
# （2026-09-28 に docker run --privileged + mount -t binfmt_misc で確認）。設定漏れではないので警告しない。
run_wrapper "${standard_path}" "${wsl_binfmt}" "${no_drive_ssh}" -V
if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux && -z "${stderr_out}" ]]; then
  pass "WSLInterop は見えるが Windows のドライブが無い（コンテナ）→ 本来の ssh を黙って使う"
else
  fail "WSLInterop は見えるが Windows のドライブが無い（コンテナ）→ 本来の ssh を黙って使う" "rc=${rc} name=$(recorded_name) stderr=${stderr_out}"
fi

echo "== 終了コードと stdin =="
export STUB_EXIT=42
run_wrapper "${standard_path}" "${wsl_binfmt}" "${windows_ssh_stub}" -V
if [[ "${rc}" -eq 42 ]]; then pass "ssh.exe の終了コードを返す"; else fail "ssh.exe の終了コードを返す" "rc=${rc}（期待 42）"; fi
run_wrapper "${standard_path}" "${plain_binfmt}" "${windows_ssh_stub}" -V
if [[ "${rc}" -eq 42 ]]; then pass "本来の ssh の終了コードを返す"; else fail "本来の ssh の終了コードを返す" "rc=${rc}（期待 42）"; fi
export STUB_EXIT=0

# herdr は Linux リモートへバイナリを ssh の stdin で送るので、バイナリの stdin が崩れないことを確かめる。
payload="${work_dir}/payload.bin"
head -c 1048576 /dev/urandom >"${payload}"
for label_binfmt in "ssh.exe:${wsl_binfmt}" "本来の ssh:${plain_binfmt}"; do
  label="${label_binfmt%%:*}"
  binfmt="${label_binfmt#*:}"
  rm -f "${STUB_RECORD}" "${STUB_STDIN}"
  run_limited env SSH_WRAPPER_BINFMT_DIR="${binfmt}" SSH_WRAPPER_WINDOWS_SSH="${windows_ssh_stub}" STUB_COPY_STDIN=1 \
    PATH="${standard_path}" "${wrapper}" -T dev 'cat > /tmp/x' <"${payload}" >/dev/null 2>&1
  if cmp -s "${payload}" "${STUB_STDIN}"; then
    pass "${label} へ 1 MiB のバイナリ stdin をそのまま渡す"
  else
    fail "${label} へ 1 MiB のバイナリ stdin をそのまま渡す" "受け取ったサイズ $(wc -c <"${STUB_STDIN}" 2>/dev/null || echo 0)"
  fi
done

echo "== 自分自身を呼ばない =="
# PATH 上にラッパー本体と symlink の両方があっても、その先の本来の ssh へ届く。
run_wrapper "${wrapper_dir}:${link_dir}:${linux_dir}:${tools_dir}" "${plain_binfmt}" "${windows_ssh_stub}" -V
if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux ]]; then
  pass "PATH 上のラッパー本体と symlink を飛ばして本来の ssh を使う"
else
  fail "PATH 上のラッパー本体と symlink を飛ばして本来の ssh を使う" "rc=${rc} name=$(recorded_name) stderr=${stderr_out}"
fi

# symlink 経由で PATH から起動されたときも同じ（~/.local/bin/ssh -> dotfiles/bin/ssh のような配置）。
rm -f "${STUB_RECORD}"
run_limited env SSH_WRAPPER_BINFMT_DIR="${plain_binfmt}" SSH_WRAPPER_WINDOWS_SSH="${windows_ssh_stub}" \
  PATH="${link_dir}:${wrapper_dir}:${linux_dir}:${tools_dir}" ssh -V </dev/null >/dev/null 2>&1
rc=$?
if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux ]]; then
  pass "symlink 経由で起動されても本来の ssh を使う"
else
  fail "symlink 経由で起動されても本来の ssh を使う" "rc=${rc} name=$(recorded_name)"
fi

run_wrapper "${wrapper_dir}:${link_dir}:${tools_dir}" "${plain_binfmt}" "${windows_ssh_stub}" -V
if [[ "${rc}" -eq 127 && "${stderr_out}" == *"本来の ssh が見つかりません"* ]]; then
  pass "本来の ssh が無い → 127 で終わり、stderr で知らせる（ループしない）"
else
  fail "本来の ssh が無い → 127 で終わり、stderr で知らせる（ループしない）" "rc=${rc}（124 は timeout）stderr=${stderr_out}"
fi

echo "== PATH の空要素（カレントディレクトリ） =="
# execvp と同じく、PATH の空要素はカレントディレクトリとして探す。先頭・途中・末尾のどれでも同じ。
# 末尾の空要素は bash の read -a が落とすので、以前は見つけられず 127 になっていた。
for path_case in "先頭:::${wrapper_dir}:${tools_dir}" "途中::${wrapper_dir}::${tools_dir}" "末尾::${wrapper_dir}:${tools_dir}:"; do
  label="${path_case%%::*}"
  path_value="${path_case#*::}"
  rm -f "${STUB_RECORD}"
  stderr_out="$(cd "${linux_dir}" && run_limited env SSH_WRAPPER_BINFMT_DIR="${plain_binfmt}" \
    SSH_WRAPPER_WINDOWS_SSH="${windows_ssh_stub}" PATH="${path_value}" "${wrapper}" -V </dev/null 2>&1 >/dev/null)"
  rc=$?
  if [[ "${rc}" -eq 0 && "$(recorded_name)" == linux ]]; then
    pass "PATH の${label}の空要素からカレントディレクトリの ssh を見つける"
  else
    fail "PATH の${label}の空要素からカレントディレクトリの ssh を見つける" "PATH=${path_value} rc=${rc} stderr=${stderr_out}"
  fi
done

echo "== 実機（本物の ssh.exe） =="
real_windows_ssh=/mnt/c/Windows/System32/OpenSSH/ssh.exe
real_interop=0
for entry in /proc/sys/fs/binfmt_misc/WSLInterop*; do [[ -e "${entry}" ]] && real_interop=1; done
if [[ "${real_interop}" -eq 1 && -x "${real_windows_ssh}" ]]; then
  version_out="$(env -u SSH_WRAPPER_BINFMT_DIR -u SSH_WRAPPER_WINDOWS_SSH timeout 20s "${wrapper}" -V 2>&1 </dev/null)"
  rc=$?
  if [[ "${rc}" -eq 0 && "${version_out}" == *OpenSSH_for_Windows* ]]; then
    pass "既定設定で本物の ssh.exe を起動する（${version_out%%$'\r'*}）"
  else
    fail "既定設定で本物の ssh.exe を起動する" "rc=${rc} out=${version_out}"
  fi
else
  skip "既定設定で本物の ssh.exe を起動する" "WSL interop か ${real_windows_ssh} が無い"
fi

echo
printf 'PASS %d / FAIL %d / SKIP %d\n' "${pass_count}" "${fail_count}" "${skip_count}"
[[ "${fail_count}" -eq 0 ]]
