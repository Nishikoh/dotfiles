#!/bin/bash
# Claude Code status line: working dir, git branch, model name, context window usage
input=$(cat)

if command -v jq >/dev/null 2>&1; then
  dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
  model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
  used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
elif command -v python3 >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
dir = (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or ""
model = (d.get("model") or {}).get("display_name") or ""
cw = d.get("context_window") or {}
used = cw.get("used_percentage")
used = "" if used is None else used
print(f"{dir}\t{model}\t{used}")
')
  IFS=$'\t' read -r dir model used <<< "$parsed"
else
  dir=""
  model=""
  used=""
fi

# Fall back to $PWD if nothing was extracted
[ -z "$dir" ] && dir="$PWD"

display_dir="${dir/#$HOME/~}"
branch=$(git -C "$dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$used" ]; then
  ctx=$(printf '%.0f%%' "$used")
else
  ctx="--"
fi

sep=$(printf ' \033[90m|\033[0m ')
dir_c=$(printf '\033[36m%s\033[0m' "$display_dir")
model_c=$(printf '\033[35m%s\033[0m' "$model")
ctx_c=$(printf '\033[33mCtx %s\033[0m' "$ctx")

if [ -n "$branch" ]; then
  branch_c=$(printf '\033[32m%s\033[0m' "$branch")
  printf '%s%s%s%s%s%s%s\n' "$dir_c" "$sep" "$branch_c" "$sep" "$model_c" "$sep" "$ctx_c"
else
  printf '%s%s%s%s%s\n' "$dir_c" "$sep" "$model_c" "$sep" "$ctx_c"
fi
