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

exit 0
