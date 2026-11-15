#!/usr/bin/env bash
# Runs each prompt in trigger-prompts.tsv with `claude -p` and checks which skill fires.
# Usage: evals/run-trigger-evals.sh [skill-name]
set -u
command -v claude >/dev/null || { echo "claude is not on PATH" >&2; exit 2; }
# Stock macOS has no timeout; coreutils installs it as gtimeout.
to=$(command -v timeout || command -v gtimeout) || { echo "timeout not found (on macOS: brew install coreutils)" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
tsv="$here/trigger-prompts.tsv"
if [ -n "${1:-}" ] && ! cut -f1 "$tsv" | grep -qxF -- "$1"; then
  echo "no prompts for skill: $1" >&2
  exit 2
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/cwd"
fail=0 errors=0 evaluated=0
off=$(python3 -I -c 'import json,os,sys
try: o = json.load(open(os.path.expanduser("~/.claude/settings.json"))).get("skillOverrides", {})
except Exception: o = {}
print(" ".join(k for k, v in o.items() if v == "off"))' 2>/dev/null)
while IFS=$'\t' read -r skill expect prompt; do
  [ -n "${1:-}" ] && [ "$1" != "$skill" ] && continue
  case " $off " in *" $skill "*) printf 'skip %-18s turned off in ~/.claude/settings.json\n' "$skill"; continue ;; esac
  dir=$work/cwd
  [ "$skill" = setup-claude-code ] && dir=$repo
  (cd "$dir" && "$to" 180 claude -p "$prompt" --model haiku --max-turns 1 \
    --output-format stream-json --verbose) >"$work/out" 2>"$work/err" </dev/null
  code=$?
  fired=$(grep -o '"name":"Skill","input":{"skill":"[^"]*"' "$work/out" | sed 's/.*"skill":"//;s/"$//' | head -1)
  # A run that used a tool ends in error_max_turns and exits 1; that is a normal run.
  result=$(grep '"type":"result"' "$work/out" | tail -1)
  error=
  if [ "$code" = 124 ]; then error="timed out after 180 s"
  elif [ -z "$result" ]; then error=$(tail -1 "$work/err"); error=${error:-"no result (exit $code)"}
  elif printf '%s' "$result" | grep -q '"is_error":true' &&
    ! printf '%s' "$result" | grep -q '"subtype":"error_max_turns"'; then
    error=$(printf '%s' "$result" | grep -o '"result":"[^"]*"' | head -1 | sed 's/^"result":"//;s/"$//')
    error=${error:-$(tail -1 "$work/err")}
  fi
  if [ -n "$error" ]; then
    errors=$((errors + 1))
    printf 'ERROR %-18s expect=%s %s: %s\n' "$skill" "$expect" "$prompt" "$error"
    continue
  fi
  evaluated=$((evaluated + 1))
  if [ "$expect" = 1 ] && [ "$fired" = "$skill" ]; then r=ok
  elif [ "$expect" = 0 ] && [ "$fired" != "$skill" ]; then r=ok
  else r=FAIL; fail=$((fail+1)); fi
  printf '%-5s %-18s expect=%s fired=%-18s %s\n' "$r" "$skill" "$expect" "${fired:--}" "$prompt"
done < "$tsv"
echo "evaluated: $evaluated, failures: $fail, errors: $errors"
[ "$evaluated" -gt 0 ] && [ "$fail" = 0 ] && [ "$errors" = 0 ]
