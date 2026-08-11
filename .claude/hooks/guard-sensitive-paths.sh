#!/usr/bin/env bash
# PreToolUse ガードフック: Bash コマンド文字列を検査し、機微パスへのアクセスを機械的に強制する。
#
# 背景: permissions.deny の Bash ルールは文字列マッチのみで、単語境界や
# 「dotenvx get は拒否するが dotenvx run は許可」のような文脈判定を表現できない。
# このフックが以下を強制する (配置: .claude/hooks/ と ~/.claude/hooks/ の2層):
#   1. data/holdout への言及       → deny (AGENTS.md 検証の規律: L2、読み書き禁止)
#   2. .env / .env.* への言及      → deny (AGENTS.md L3: API キー管理は人間専権)
#   3. dotenvx get / decrypt       → deny (復号値の出力・平文化。dotenvx run は許可)
#   4. ENV=prod を伴う実行         → ask  (AGENTS.md L2/L3: 実弾・本番系は人間の事前承認)
#   5. git push --force / -f       → ask  (履歴改変は不可逆)
#   6. ulimit -v/-m/-d が過大      → deny (利用可能メモリの90%超。ULIMIT_MEM_OVERRIDE=1 で ask に緩和)
#   7. ulimit -m の単独使用        → ask  (Linux は RLIMIT_RSS を無視するため実効性ゼロ)
#   8. cgroup MemoryMax が過大     → deny (実装メモリの90%超。ULIMIT_MEM_OVERRIDE=1 で ask に緩和)
#
# 出力契約: PreToolUse の hookSpecificOutput.permissionDecision (deny/ask) を JSON で返す。
# 該当しなければ何も出力せず exit 0 (許可判断は通常の permissions フローに委ねる)。
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

emit_decision() {
  # $1: deny|ask, $2: 理由
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

# 1) data/holdout (パス区切りの連続スラッシュも吸収)
if printf '%s' "$cmd" | grep -qE 'data/+holdout'; then
  emit_decision deny "data/holdout はアクセス禁止 (AGENTS.md 検証の規律 L2: OOS/ホールドアウトは人間専権)"
  exit 0
fi

# 2) .env / .env.keys / .env.prod 等 (venv・.envrc・my_env 等は誤検知しない境界指定)
#    末尾境界にグロブ文字 * ? [ を含め、`cat .env*` のようなシェル展開経由の回避も塞ぐ。
if printf '%s' "$cmd" | grep -qE "(^|[ /\"'=(])\\.env(\\.[A-Za-z0-9_]+)*([ \"'<>|;&)*?[]|\$)"; then
  emit_decision deny ".env 系ファイルへの Bash 経由アクセスは禁止 (AGENTS.md L3: 認証情報・API キーの管理は人間専権)"
  exit 0
fi

# 3) dotenvx get / decrypt は復号値を露出する (dotenvx run/set/encrypt は対象外)
if printf '%s' "$cmd" | grep -qE "(^|[ /|;&\"'])dotenvx +(get|decrypt)( |\$)"; then
  emit_decision deny "dotenvx get/decrypt は復号された機密値を露出するため禁止 (AGENTS.md L3)。環境変数の受け渡しは dotenvx run を使う"
  exit 0
fi

# 4) ENV=prod (単語境界で判定。ENV=stg は対象外。ENV="prod"/'prod' のクォート回避も塞ぐ)
if printf '%s' "$cmd" | grep -qE "(^|[ ;&|])ENV=[\"']?prod[\"']?([ ;&|]|\$)"; then
  emit_decision ask "ENV=prod を伴う実行は L2/L3 (実弾・本番系)。人間の事前承認が必要 (AGENTS.md)"
  exit 0
fi

# 5) git push --force / -f (履歴改変は不可逆。--force-with-lease も --force に含まれる)
#    [^;&|]* で push 直後〜次のコマンド区切りまでに限定し、`git push origin x && rm -f y` の
#    -f を誤検知しない。+refspec 形式の強制 push は曖昧なため対象外(残存ギャップ)。
if printf '%s' "$cmd" | grep -qE 'git +push[^;&|]*(--force|[[:space:]]-f([[:space:]]|$))'; then
  emit_decision ask "git push --force は履歴改変で不可逆。人間の事前確認が必要 (共有ブランチ・worktree 運用の保護)"
  exit 0
fi

# 6) ulimit のメモリ上限 (-v 仮想 / -m RSS / -d データ、KB 単位) の過大指定ガード
#    意図: 利用可能メモリの 90% を超える上限は「実質無制限」であり、OOM で
#    ホストごと巻き込む。まずメモリ使用量そのものを削減させ、それでも足りない
#    場合だけ ULIMIT_MEM_OVERRIDE=1 で人間の判断 (ask) に上げる。
#    静的に数値と確定できない値 (変数・unlimited・ネスト括弧付き算術式) は
#    fail-closed で deny する (検証不能なものを通さない)。
#    残存ギャップ (対象外): prlimit / systemd-run --property=MemoryMax /
#    cgroup 直書き / ulimit -l (ロック) -s (スタック) / ネスト括弧を含む
#    算術式 $(( (2+3)*1024 )) は「検証不能」扱いの deny に落ちる /
#    /proc/meminfo が読めない環境では判定自体をスキップ。
if printf '%s' "$cmd" | grep -qE '(^|[;&|`([:space:]])ulimit[[:space:]][^;&|]*-[A-Za-z]*[vmd]'; then
  mem_src="MemAvailable"
  avail_kb="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
  if [ -z "$avail_kb" ]; then
    mem_src="MemFree"
    avail_kb="$(awk '/^MemFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
  fi
  if [ -n "$avail_kb" ]; then
    cap_kb=$(( avail_kb * 90 / 100 ))
    # ulimit から次のコマンド区切りまでのセグメントに限定して値を抽出
    # (grep -v など他コマンドの -v を誤検知しないため)
    vals="$(printf '%s' "$cmd" \
      | grep -oE '(^|[;&|`([:space:]])ulimit[[:space:]][^;&|]*' \
      | grep -oE -- '-[A-Za-z]*[vmd][A-Za-z]*[[:space:]]+(\$\(\([^)]*\)\)|[^[:space:];&|)]+)' \
      | sed -E 's/^-[A-Za-z]*[vmd][A-Za-z]*[[:space:]]+//' || true)"
    worst_kb=""; bad_tok=""
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      kb=""
      if printf '%s' "$tok" | grep -qE '^[0-9]+$'; then
        # 16桁以上は bash 算術があふれる前に確実な超過として扱う
        if [ "${#tok}" -le 15 ]; then kb="$tok"; else kb=$(( cap_kb + 1 )); fi
      elif printf '%s' "$tok" | grep -qE '^\$\(\([0-9*+/() [:space:]-]+\)\)$'; then
        # 数字と算術演算子のみ確認済みの $((...)) のみ評価 (変数・コマンド置換は上の正規表現で除外済み)
        # $(( expr_body )) は bash が算術式内の変数名を再帰評価する仕様を利用。
        # 構文エラー (例 `8*`) はサブシェルごと死ぬので、サブシェル全体に
        # 2>/dev/null を掛けてエラー出力を捨て、失敗は外側の `|| kb=""` で吸収する
        # (`$(... || true)` 形だと展開エラー時に `|| true` に到達できず set -e でフックが落ちる)。
        expr_body="${tok#\$\(\(}"; expr_body="${expr_body%\)\)}"
        kb="$( (printf '%s' "$(( expr_body ))") 2>/dev/null )" || kb=""
      fi
      if [ -z "$kb" ]; then
        bad_tok="$tok"
      elif [ "$kb" -gt "$cap_kb" ]; then
        if [ -z "$worst_kb" ] || [ "$kb" -gt "$worst_kb" ]; then worst_kb="$kb"; fi
      fi
    done <<< "$vals"
    if [ -n "$worst_kb" ] || [ -n "$bad_tok" ]; then
      if [ -n "$worst_kb" ]; then
        detail="要求 ${worst_kb}KB / ${mem_src} ${avail_kb}KB の90% = ${cap_kb}KB"
      else
        detail="値 '${bad_tok}' は静的検証不能(変数・unlimited 等)。${cap_kb}KB 以下の数値リテラル(KB)で指定し直すこと (${mem_src} ${avail_kb}KB の90%)"
      fi
      if printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|])ULIMIT_MEM_OVERRIDE=1([[:space:];&|]|$)'; then
        emit_decision ask "ulimit のメモリ上限が利用可能メモリの90%超だが ULIMIT_MEM_OVERRIDE=1 が指定されている: ${detail}。エージェントはメモリ削減を試みた上で90%超を要求している。許可するか、値の縮小・他プロセス停止・分割実行などを指示せよ"
      else
        emit_decision deny "ulimit のメモリ上限が過大 (利用可能メモリの90%超): ${detail}。まずメモリ使用量の削減(不要プロセス停止・バッチサイズ縮小・データ分割など)を可能な限り実行し、${cap_kb}KB 以下の値で再試行すること。削減を尽くしても不足する場合のみ ULIMIT_MEM_OVERRIDE=1 を前置して再実行(ユーザーに承認を確認する)"
      fi
      exit 0
    fi
  fi
fi

# 7) ulimit -m (RLIMIT_RSS) は Linux では無効という注意喚起
#    意図: -m は「実メモリを制限したつもり」になれてしまうが、Linux カーネルは
#    RLIMIT_RSS を無視する (2026-07-27 実測: 500MB 設定で 2GB 使い切って完走)。
#    6) の過大値チェックを通過した「一見妥当な」-m ほど危険なので、ここで人間に上げる。
#    -v / -d を併用している場合はそちらが実際に効くため対象外にする (二重通知を避ける)。
if printf '%s' "$cmd" | grep -qE '(^|[;&|`([:space:]])ulimit[[:space:]][^;&|]*-[A-Za-z]*m' \
   && ! printf '%s' "$cmd" | grep -qE '(^|[;&|`([:space:]])ulimit[[:space:]][^;&|]*-[A-Za-z]*[vd]'; then
  emit_decision ask "ulimit -m (RLIMIT_RSS) は Linux では無視されるため、実メモリ制限として機能しない (実測で確認済み)。実メモリを制限したい場合は cgroup を使うこと: systemd-run --user --scope -p MemoryMax=<N>K -p MemorySwapMax=0 <cmd>。意図的に -m を使う (他OS向け・互換目的等) なら許可を指示せよ"
  exit 0
fi

# 8) cgroup (systemd-run の MemoryMax) の過大指定ガード
#    意図: 6) の残存ギャップだった systemd-run 経路を塞ぐ。DuckDB/sqlmesh の
#    メモリ制限は ulimit -Sv ではなく cgroup を使うのが正しい (ulimit -Sv は
#    仮想アドレス空間の制限で、DuckDB は実使用量の約2.6倍を予約するため誤検知する:
#    LRN-20260727-001)。正しい手段へ移行した以上、その手段側にも上限ガードが要る。
#    判定基準が 6) と違う点: cgroup は超過してもそのプロセスだけが SIGKILL され
#    ホスト全体を巻き込まないため、MemAvailable ではなく MemTotal 基準で判定する
#    (他プロセスの一時的な使用量に左右されず、意図した割合指定を通せる)。
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])systemd-run([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qE 'MemoryMax='; then
  total_kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
  if [ -n "$total_kb" ]; then
    cg_cap_kb=$(( total_kb * 90 / 100 ))
    cg_worst_kb=""; cg_bad_tok=""
    # MemoryMax= の右辺だけを抽出する (--property=MemoryMax=... / -p MemoryMax=... 両対応)
    cg_vals="$(printf '%s' "$cmd" \
      | grep -oE 'MemoryMax=[^[:space:];&|"'"'"']+' \
      | sed -E 's/^MemoryMax=//' || true)"
    while IFS= read -r cg_tok; do
      [ -z "$cg_tok" ] && continue
      cg_kb=""
      case "$cg_tok" in
        infinity|INFINITY)
          # 明示的な無制限。cap 超過として扱う。
          cg_kb=$(( cg_cap_kb + 1 )) ;;
        *%)
          # systemd の割合指定 (MemTotal に対する割合)
          cg_pct="${cg_tok%\%}"
          if printf '%s' "$cg_pct" | grep -qE '^[0-9]+$' && [ "${#cg_pct}" -le 5 ]; then
            cg_kb=$(( total_kb * cg_pct / 100 ))
          fi ;;
        *[Kk]) cg_num="${cg_tok%[Kk]}"
          printf '%s' "$cg_num" | grep -qE '^[0-9]{1,15}$' && cg_kb="$cg_num" ;;
        *[Mm]) cg_num="${cg_tok%[Mm]}"
          printf '%s' "$cg_num" | grep -qE '^[0-9]{1,12}$' && cg_kb=$(( cg_num * 1024 )) ;;
        *[Gg]) cg_num="${cg_tok%[Gg]}"
          printf '%s' "$cg_num" | grep -qE '^[0-9]{1,9}$' && cg_kb=$(( cg_num * 1024 * 1024 )) ;;
        *[Tt]) cg_num="${cg_tok%[Tt]}"
          printf '%s' "$cg_num" | grep -qE '^[0-9]{1,6}$' && cg_kb=$(( cg_num * 1024 * 1024 * 1024 )) ;;
        *)
          # サフィックス無しは systemd ではバイト単位
          printf '%s' "$cg_tok" | grep -qE '^[0-9]{1,18}$' && cg_kb=$(( cg_tok / 1024 )) ;;
      esac
      if [ -z "$cg_kb" ]; then
        cg_bad_tok="$cg_tok"
      elif [ "$cg_kb" -gt "$cg_cap_kb" ]; then
        if [ -z "$cg_worst_kb" ] || [ "$cg_kb" -gt "$cg_worst_kb" ]; then cg_worst_kb="$cg_kb"; fi
      fi
    done <<< "$cg_vals"
    if [ -n "$cg_worst_kb" ] || [ -n "$cg_bad_tok" ]; then
      if [ -n "$cg_worst_kb" ]; then
        cg_detail="要求 ${cg_worst_kb}KB / MemTotal ${total_kb}KB の90% = ${cg_cap_kb}KB"
      else
        cg_detail="値 '${cg_bad_tok}' は静的検証不能(変数・式等)。数値リテラル(例 ${cg_cap_kb}K)で指定し直すこと (MemTotal ${total_kb}KB の90% = ${cg_cap_kb}KB)"
      fi
      if printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|])ULIMIT_MEM_OVERRIDE=1([[:space:];&|]|$)'; then
        emit_decision ask "cgroup MemoryMax が実装メモリの90%超だが ULIMIT_MEM_OVERRIDE=1 が指定されている: ${cg_detail}。許可するか、値の縮小・分割実行などを指示せよ"
      else
        emit_decision deny "cgroup MemoryMax が過大 (実装メモリの90%超): ${cg_detail}。まず処理の分割・DuckDB memory_limit の縮小などを試し、${cg_cap_kb}KB 以下で再試行すること。削減を尽くしても不足する場合のみ ULIMIT_MEM_OVERRIDE=1 を前置して再実行(ユーザーに承認を確認する)"
      fi
      exit 0
    fi
  fi
fi

exit 0
