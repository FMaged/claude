---
name: git-branch
description: Use when the user wants to create, name, or rename a git branch (e.g. "make a branch", "new branch for this", "what should I call the branch"). Names branches like "Refactor/no-ref/repair-and-completion".
---

# Git Branch

## Format

```
<Type>/<ref>/<short-description>
```

- **Type** – capitalized: `Feature`, `Fix`, `Hotfix`, `Refactor`, `Test`, `Docs`, `Chore`.
- **ref** – the ticket or issue id (e.g. `JIRA-123`, `42`). If there is none, use `no-ref`.
- **short-description** – 2–5 lowercase words that say what the branch is about, joined with hyphens.

Git does not allow spaces in branch names, so always use hyphens instead of spaces. Also avoid `~ ^ : ? * [ \` and `..`.

## Examples

- `Refactor/no-ref/repair-and-completion`
- `Fix/JIRA-482/guest-email-umlaut-confirmation`
- `Test/no-ref/anonymous-copy-list-access`
- `Feature/57/reorder-copy-list-rows`

## Steps

1. Work out the Type and description from what the user says (or from the current changes with `git status` / `git diff`).
2. Ask for the ticket id only if the user seems to have one and did not give it; otherwise use `no-ref`.
3. Check the name with `git check-ref-format --branch "<name>"`.
4. Create and switch to it with `git switch -c "<name>"` (or rename the current one with `git branch -m "<name>"` if the user asks to rename).
5. Show the result with `git branch --show-current`.
