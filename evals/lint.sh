#!/usr/bin/env bash
# Checks the repo's skills, agents, evals, and settings for mistakes that do not need Claude to find.
# Usage: evals/lint.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
cd "$repo" || exit 1
fail=0

problem() { echo "FAIL: $*"; fail=$((fail + 1)); }

frontmatter_field() {
  # Prints the value of a top-level frontmatter field, without surrounding quotes.
  sed -n '1,/^---$/!d;p' "$1" | sed -n "s/^$2: *\"\{0,1\}\(.*[^\"]\)\"\{0,1\} *$/\1/p" | head -1
}

# Frontmatter: opens on line 1 and closes within 30 lines.
for file in skills/*/SKILL.md .claude/skills/*/SKILL.md agents/*.md; do
  if [ "$(head -1 "$file")" != "---" ]; then
    problem "$file has no frontmatter"
  elif ! sed -n '2,30p' "$file" | grep -qx -- '---'; then
    problem "$file: frontmatter has no closing --- in the first 30 lines"
  fi
done

# Frontmatter is valid YAML with string name and description, when PyYAML is installed.
if python3 -I -c 'import yaml' 2>/dev/null; then
  while IFS= read -r line; do
    problem "$line"
  done < <(python3 -I - skills/*/SKILL.md .claude/skills/*/SKILL.md agents/*.md <<'PY'
import sys, yaml
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().split("\n")
    if lines[0] != "---" or "---" not in lines[1:30]:
        continue  # reported above
    try:
        data = yaml.safe_load("\n".join(lines[1:lines.index("---", 1)]))
    except yaml.YAMLError as e:
        print(f"{path}: frontmatter is not valid YAML: {str(e).splitlines()[0]}")
        continue
    if not isinstance(data, dict):
        print(f"{path}: frontmatter is not a mapping")
        continue
    for key in ("name", "description"):
        if not isinstance(data.get(key), str) or not data[key].strip():
            print(f"{path}: {key} is missing or not a string")
PY
  )
else
  echo "note: PyYAML not installed, frontmatter YAML not parsed"
fi

# Skills: name matches the folder, and the description is present.
for skill in skills/*/SKILL.md .claude/skills/*/SKILL.md; do
  dir=$(basename "$(dirname "$skill")")
  name=$(frontmatter_field "$skill" name)
  [ "$name" = "$dir" ] || problem "$skill: name '$name' is not the folder name '$dir'"
  [ -n "$(frontmatter_field "$skill" description)" ] || problem "$skill has no description"
done

# Agents: name matches the file, and every preloaded skill exists.
for agent in agents/*.md; do
  base=$(basename "$agent" .md)
  name=$(frontmatter_field "$agent" name)
  [ "$name" = "$base" ] || problem "$agent: name '$name' is not the file name '$base'"
  while read -r s; do
    [ -f "skills/$s/SKILL.md" ] || problem "$agent preloads skill '$s', which does not exist"
  done < <(sed -n '1,/^---$/!d;p' "$agent" | sed -n '/^skills:/,/^[a-z]/{s/^ *- *//p;}')
done

# Cross-references: a backticked name that looks like a skill or agent must exist.
# Covers "use `x`", "run `x`", "`x` skill", every `*-review`/`*-reviewer`, and every `z2p*`.
known='hand-off|no-ref|in-memory|one-click|unsafe-inline|adapter-static'
# shellcheck disable=SC2016 # the backticks are literal text to match
refs=$(grep -rhoE '(^|[^`])`[a-z0-9]+(-[a-z0-9]+)+`( skill)?|(use|Use|run|runs|with|see) `[a-z0-9]+(-[a-z0-9]+)+`' skills agents .claude |
  grep -oE '`[a-z0-9]+(-[a-z0-9]+)+`' | tr -d '`' | sort -u)
for ref in $refs; do
  case "$ref" in
    *-reviewer) [ -f "agents/$ref.md" ] || problem "agent '$ref' is referenced but does not exist" ;;
    *-review|z2p*|*-writing|*-design|*-planner|*-brief|*-runner|*-to-tasks|*-builds|*-pipelines|*-skill)
      echo "$ref" | grep -qE "^($known)$" && continue
      [ -d "skills/$ref" ] || [ -d ".claude/skills/$ref" ] || problem "skill '$ref' is referenced but does not exist" ;;
  esac
done

# A skill named in "use `x` for/when/if" must be in the repo, or be one of these outside
# skills (claude.ai synced), which the text must call optional.
external='incident-triage|observability'
# shellcheck disable=SC2016 # the backticks are literal text to match
named=$(grep -rhoE '(use|Use|run|Run) `[a-z0-9]+(-[a-z0-9]+)*` (for|when|if)' skills agents .claude |
  grep -oE '`[^`]+`' | tr -d '`' | sort -u)
for ref in $named; do
  echo "$ref" | grep -qE "^($external)$" && continue
  [ -d "skills/$ref" ] || [ -d ".claude/skills/$ref" ] || [ -f "agents/$ref.md" ] ||
    problem "'$ref' is named as a skill but is neither in the repo nor in the external list"
done

# No machine-specific paths, no secrets (requirement N1).
# PLAN.md, REQUIREMENTS.md, and TASKS.md may name the path they forbid.
# 31bf3856ad364e35 is Microsoft's public key token, in every unattend file.
grep -rn '/home/[a-z]' skills agents settings .claude install.sh README.md CLAUDE.md evals/run-trigger-evals.sh evals/test-install.sh evals/trigger-prompts.tsv && problem "found a /home/ path"
# Only the file and line are printed, so a real secret does not land in a CI log.
found=$(grep -rnEi '(api[_-]?key|secret|token|password)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_/+-]*[0-9][A-Za-z0-9_/+-]*' \
  --exclude-dir=.git --exclude-dir=.terraform . | grep -v '^./evals/lint.sh' | grep -v 'publicKeyToken="31bf3856ad364e35"' | grep -E '[:=][[:space:]]*["'"'"']?[A-Za-z0-9_/+-]{16,}')
[ -n "$found" ] && { echo "$found" | cut -d: -f1,2; problem "found what looks like a secret"; }
found=$(grep -rnE 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}' --exclude-dir=.git --exclude-dir=.terraform .)
[ -n "$found" ] && { echo "$found" | cut -d: -f1,2; problem "found a credential"; }

# Evals: every prompt names a skill that exists and has a 0/1 expectation.
while IFS=$'\t' read -r skill expect prompt; do
  [ -d "skills/$skill" ] || [ -d ".claude/skills/$skill" ] || problem "trigger-prompts.tsv names unknown skill '$skill'"
  [ "$expect" = 0 ] || [ "$expect" = 1 ] || problem "trigger-prompts.tsv: expect must be 0 or 1 for '$prompt'"
  [ -n "$prompt" ] || problem "trigger-prompts.tsv: empty prompt for $skill"
done < evals/trigger-prompts.tsv
for skill in skills/*/ .claude/skills/*/; do
  s=$(basename "$skill")
  [ "$(grep -c "^$s	1	" evals/trigger-prompts.tsv)" -ge 2 ] || problem "skill '$s' needs 2 prompts that should fire"
  [ "$(grep -c "^$s	0	" evals/trigger-prompts.tsv)" -ge 2 ] || problem "skill '$s' needs 2 prompts that should not fire"
done

# Settings must be valid JSON.
python3 -I -m json.tool settings/settings.json >/dev/null || problem "settings/settings.json is not valid JSON"

# Worked examples: checked with their own tool when it is installed.
if command -v terraform >/dev/null; then
  terraform fmt -check -recursive evals/examples/terraform || problem "terraform fmt in evals/examples/terraform"
  for root in evals/examples/terraform/infra/envs/*/; do
    (cd "$root" && terraform init -backend=false -input=false -lockfile=readonly >/dev/null && terraform validate) ||
      problem "terraform validate in $root"
  done
else
  echo "note: terraform not installed, examples not validated"
fi

if command -v packer >/dev/null; then
  packer fmt -check -recursive evals/examples/packer || problem "packer fmt in evals/examples/packer"
  for image in evals/examples/packer/*/; do
    { packer init "$image" >/dev/null &&
      PKR_VAR_build_password=lint-only PKR_VAR_git_sha=0000000 packer validate "$image" >/dev/null; } ||
      problem "packer validate in $image"
  done
else
  echo "note: packer not installed, examples not validated"
fi

if command -v pwsh >/dev/null; then
  pwsh -NoProfile -NonInteractive -File evals/check-powershell.ps1 || problem "PowerShell examples"
else
  echo "note: pwsh not installed, PowerShell examples not checked"
fi

# Ansible's local temporary files must be writable; use the existing task-specific cache.
if command -v ansible-lint >/dev/null && command -v ansible-playbook >/dev/null; then
  (
    cd evals/examples/ansible || exit 1
    export ANSIBLE_LOCAL_TEMP="${TMPDIR:-/tmp}/ansible-local"
    mkdir -p "$ANSIBLE_LOCAL_TEMP"
    ansible-lint || exit 1
    ansible-playbook -i inventory/staging playbooks/app.yml --syntax-check
  ) || problem "Ansible example"
else
  echo "note: ansible-lint or ansible-playbook not installed, Ansible example not validated"
fi

# Shell scripts.
if command -v shellcheck >/dev/null; then
  shellcheck install.sh evals/*.sh evals/examples/bash/*.sh || problem "shellcheck"
else
  echo "note: shellcheck not installed, skipped"
fi

# The Bash example's test needs no network: it serves its archives as file:// URLs.
if out=$(evals/examples/bash/test-fetch-tool.sh 2>&1); then :; else
  echo "$out" | grep -v '^ok '
  problem "Bash example"
fi

echo "lint failures: $fail"
[ "$fail" = 0 ]
