#!/usr/bin/env bash
# Runs each prompt in trigger-prompts.tsv with `claude -p` and checks which skill fires.
# Usage: evals/run-trigger-evals.sh [skill-name]
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
work=$(mktemp -d)
fail=0
while IFS=$'\t' read -r skill expect prompt; do
  [ -n "${1:-}" ] && [ "$1" != "$skill" ] && continue
  dir=$work
  [ "$skill" = setup-claude-code ] && dir=$repo
  fired=$(cd "$dir" && timeout 180 claude -p "$prompt" --model haiku --max-turns 1 \
    --output-format stream-json --verbose 2>/dev/null |
    grep -o '"name":"Skill","input":{"skill":"[^"]*"' | sed 's/.*"skill":"//;s/"$//' | head -1)
  if [ "$expect" = 1 ] && [ "$fired" = "$skill" ]; then r=ok
  elif [ "$expect" = 0 ] && [ "$fired" != "$skill" ]; then r=ok
  else r=FAIL; fail=$((fail+1)); fi
  printf '%-4s %-18s expect=%s fired=%-18s %s\n' "$r" "$skill" "$expect" "${fired:--}" "$prompt"
done < "$here/trigger-prompts.tsv"
rmdir "$work" 2>/dev/null
echo "failures: $fail"
