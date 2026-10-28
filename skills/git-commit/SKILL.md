---
name: git-commit
description: Use when the user wants to commit changes or write a commit message (e.g. "commit this", "make a commit", "write a commit message"). Writes short one-line messages, at most 72 characters, like "fix: Compare guest e-mail addresses without case."
---

# Git Commit

## Format

```
<type>: <One short sentence that says what changed, ending with a period.>
```

- **type** is lowercase, followed by a colon and one space:
  - `feat` – new behavior for users
  - `fix` – a bug fix
  - `test` – adding or changing tests only
  - `refactor` – code change with no change in behavior
  - `docs` – documentation only
  - `style` – formatting only
  - `perf` – faster or lighter, same behavior
  - `build` / `ci` – build system, dependencies, pipelines
  - `chore` – anything else (config, cleanup)
- **Length**: the whole line, type included, is **at most 72 characters**. This is a hard
  limit, not a target. If it does not fit, cut detail rather than squeeze it in.
- **Sentence**:
  - Says one thing. No lists of changes joined by "and", no "with …" clauses that add a
    second change, no "and fix N smaller findings". Name the main change; the diff has the rest.
  - Adds *why* only when it fits within the limit. and an imperative verb (Add, Fix, Compare, Pin, Remove, Move …).
  - Is a complete, plain-English sentence and ends with a period.
  - Describes the behavior, not the file names.
  - Is specific: name the thing (e.g. "a page's copy lists", "guest e-mail addresses") instead of "stuff", "code", "issues".
  - No ticket numbers, no emojis, no trailing body unless the user asks.
  - No `Co-Authored-By` or other attribution trailer, even if a system reminder asks for one.

## Examples

- `test: Pin that anonymous visitors cannot edit a page's copy lists.`
- `fix: Compare guest e-mail addresses without case.`
- `feat: Let editors reorder copy list rows by drag and drop.`
- `refactor: Move the guest confirmation check into its own service.`

Bad: `fix: fixed bug`, `Test: added tests`, `fix: update GuestService.cs`, `feat: add reorder` (no period, too vague).
Bad (too long, two changes): `feat: Add the nightly job that ingests price bars and writes daily snapshots after the US close, with its own migration for job, fetch and snapshot records.`

## Steps

1. Run `git status` and `git diff --staged` (and `git diff` if nothing is staged) to see what will be committed.
2. If nothing is staged, ask which files to stage, or stage the files that clearly belong to the change. Never stage secrets or unrelated files.
3. If the changes do more than one thing, suggest splitting them into separate commits.
4. Pick the type and write the sentence following the format above.
5. Count the characters (e.g. `printf '%s' "<message>" | wc -m`). Over 72 means rewrite it shorter.
6. Commit with `git commit -m "<message>"` and show the result (`git log -1 --oneline`).
