#!/usr/bin/env bash
# Runs install.sh against an empty home and checks requirements R2, R3, and R4.
# Usage: evals/test-install.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
fail=0
check() { if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3 (got '$1', want '$2')"; fail=$((fail + 1)); fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
skills=$(find "$repo"/skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
agents=$(find "$repo"/agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
total=$((skills * 2 + agents))

summary=$("$repo/install.sh" | tail -1)
check "$summary" "Summary: linked $total, already OK 0, conflicts 0, removed 0, skipped 0" "fresh home links every skill twice and every agent once"
check "$(readlink "$HOME/.claude/skills/z2p")" "$repo/skills/z2p" "claude skill link points into the repo"
check "$(readlink "$HOME/.agents/skills/z2p")" "$repo/skills/z2p" "codex skill link points into the repo"
check "$(readlink "$HOME/.claude/agents/sql-reviewer.md")" "$repo/agents/sql-reviewer.md" "agent link points into the repo"
check "$(cd "$HOME/.agents" && echo *)" "skills" "codex gets no agents"

summary=$("$repo/install.sh" | tail -1)
check "$summary" "Summary: linked 0, already OK $total, conflicts 0, removed 0, skipped 0" "second run changes nothing (R2)"

summary=$("$repo/install.sh" --dry-run | tail -1)
check "$summary" "Summary: linked 0, already OK $total, conflicts 0, removed 0, skipped 0" "dry run reports the same"

rm "$HOME/.claude/skills/git-commit"
mkdir "$HOME/.claude/skills/git-commit"
echo mine > "$HOME/.claude/skills/git-commit/SKILL.md"
out=$("$repo/install.sh"); code=$?
check "$code" "1" "a real folder in the way makes the installer exit 1"
check "$(echo "$out" | grep -c '^conflict: ')" "1" "the real folder is reported as a conflict"
check "$(cat "$HOME/.claude/skills/git-commit/SKILL.md")" "mine" "the real folder is left alone (R3)"

out=$("$repo/install.sh" --backup); code=$?
check "$code" "0" "--backup resolves the conflict"
check "$(readlink "$HOME/.claude/skills/git-commit")" "$repo/skills/git-commit" "--backup links the skill"
check "$(cat "$HOME"/.claude/backups/install-*/skills/git-commit/SKILL.md)" "mine" "--backup kept my folder"

home4="$tmp/home4"
HOME="$home4" "$repo/install.sh" >/dev/null
for s in git-branch git-commit; do
  rm "$home4/.claude/skills/$s"
  mkdir "$home4/.claude/skills/$s"
  echo mine > "$home4/.claude/skills/$s/SKILL.md"
done
out=$(HOME="$home4" "$repo/install.sh" --backup --skip git-branch); code=$?
check "$code" "0" "--skip with --backup exits 0"
check "$(echo "$out" | grep -c '^skip: ')" "1" "the declined conflict is reported as skip"
check "$(cat "$home4/.claude/skills/git-branch/SKILL.md")" "mine" "--skip leaves the declined folder alone (R3)"
check "$(readlink "$home4/.claude/skills/git-commit")" "$repo/skills/git-commit" "--backup still links the approved one"
check "$(ls "$home4"/.claude/backups/install-*/skills)" "git-commit" "only the approved folder is backed up"

cp -R "$repo" "$tmp/repo2"
rm -rf "$tmp/repo2/.git"
HOME="$tmp/home2" "$tmp/repo2/install.sh" >/dev/null
rm -rf "$tmp/repo2/skills/git-branch"
summary=$(HOME="$tmp/home2" "$tmp/repo2/install.sh" | tail -1)
check "$summary" "Summary: linked 0, already OK $((total - 2)), conflicts 0, removed 2, skipped 0" "a deleted skill has its links removed (R4)"
rm "$tmp/repo2/skills/git-commit/SKILL.md"
summary=$(HOME="$tmp/home2" "$tmp/repo2/install.sh" | tail -1)
check "$summary" "Summary: linked 0, already OK $((total - 4)), conflicts 0, removed 2, skipped 0" "a skill without SKILL.md has its links removed"

HOME="$tmp/home3" "$repo/install.sh" --target codex >/dev/null
check "$(find "$tmp/home3" -maxdepth 1 -name .claude | wc -l | tr -d ' ')" "0" "--target codex does not touch ~/.claude"
check "$(find "$tmp/home3/.agents/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "$skills" "--target codex links every skill"

"$repo/install.sh" --target nope >/dev/null 2>&1; check "$?" "2" "an unknown target is rejected"
"$repo/install.sh" --what >/dev/null 2>&1; check "$?" "2" "an unknown option is rejected"

echo "install test failures: $fail"
[ "$fail" = 0 ]
